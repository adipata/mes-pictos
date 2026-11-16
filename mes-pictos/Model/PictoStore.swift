import Foundation
import SwiftData
import UIKit
import PictoCore

/// All changes to pages and pictograms go through here.
@MainActor
struct PictoStore {
    let context: ModelContext

    // MARK: Queries

    func allPages() -> [Page] {
        let descriptor = FetchDescriptor<Page>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func normalPages() -> [Page] {
        allPages().filter { $0.kind == .normal }
    }

    /// The permanent bar. If two devices created one before syncing, the oldest is used.
    func permanentBar() -> Page? {
        Self.permanentBar(in: allPages())
    }

    static func permanentBar(in pages: [Page]) -> Page? {
        pages.filter { $0.kind == .permanentBar }.min { $0.createdAt < $1.createdAt }
    }

    func placement(withID id: UUID) -> Placement? {
        var descriptor = FetchDescriptor<Placement>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: Pages

    @discardableResult
    func addPage(title: String, columns: Int = 2, rows: Int = 2) -> Page {
        let pages = normalPages()
        let next = (pages.map(\.sortIndex).max() ?? -1) + 1
        let page = Page(title: title, columns: columns, rows: rows, sortIndex: next)
        page.color = Self.nextColor(after: pages)
        context.insert(page)
        save()
        return page
    }

    /// A colour not used by the last pages, so neighbouring tabs differ.
    static func nextColor(after pages: [Page]) -> PageColor {
        let recent = Set(pages.enumerated().suffix(PageColor.allCases.count - 1).map { $1.tabColor(atIndex: $0) })
        let candidate = PageColor.automatic(forIndex: pages.count)
        if !recent.contains(candidate) { return candidate }
        return PageColor.allCases.first { !recent.contains($0) } ?? candidate
    }

    func delete(_ page: Page) {
        for placement in page.placements ?? [] {
            removeWithoutSaving(placement)
        }
        context.delete(page)
        save()
    }

    /// Hides a page from the child, keeping it and its cards for later.
    func setHidden(_ page: Page, _ hidden: Bool) {
        page.isHidden = hidden
        save()
    }

    /// Moves a page one position left (-1) or right (+1) among the normal pages.
    func movePage(_ page: Page, by offset: Int) {
        var pages = normalPages()
        guard let index = pages.firstIndex(where: { $0.id == page.id }) else { return }
        let target = index + offset
        guard pages.indices.contains(target) else { return }
        pages.swapAt(index, target)
        for (position, page) in pages.enumerated() {
            page.sortIndex = position
        }
        save()
    }

    /// Changes the grid size. Returns false when there are more pictograms than slots.
    @discardableResult
    func resize(_ page: Page, columns: Int, rows: Int) -> Bool {
        let newSize = GridSize(columns: columns, rows: rows)
        let placements = page.placements ?? []
        var slots: [UUID: Int] = [:]
        for placement in placements {
            slots[placement.id] = placement.slot
        }
        guard let mapping = GridMath.resize(slots, from: page.gridSize, to: newSize) else { return false }
        for placement in placements {
            if let slot = mapping[placement.id] {
                placement.slot = slot
            }
        }
        page.columns = newSize.columns
        page.rows = newSize.rows
        save()
        return true
    }

    // MARK: Pictograms

    /// Creates a pictogram and places it on a page, in the given slot or the first free one.
    @discardableResult
    func createPictogram(
        label: String,
        spokenText: String? = nil,
        imageData: Data? = nil,
        recordingData: Data? = nil,
        source: PictogramSource = .photo,
        sourceRef: String? = nil,
        licence: String? = nil,
        wordType: WordType = .noun,
        on page: Page,
        slot: Int? = nil
    ) -> Placement? {
        let placement = insertPictogram(
            label: label, spokenText: spokenText, imageData: imageData, recordingData: recordingData,
            source: source, sourceRef: sourceRef, licence: licence, wordType: wordType, on: page, slot: slot
        )
        if placement != nil { save() }
        return placement
    }

    /// Same as `createPictogram`, without saving. Used for batches.
    @discardableResult
    private func insertPictogram(
        label: String,
        spokenText: String?,
        imageData: Data?,
        recordingData: Data?,
        source: PictogramSource,
        sourceRef: String?,
        licence: String?,
        wordType: WordType = .noun,
        on page: Page,
        slot: Int?
    ) -> Placement? {
        let target: Int
        if let slot, page.gridSize.contains(slot), page.placement(at: slot) == nil {
            target = slot
        } else if let free = GridMath.firstFreeSlot(occupied: page.occupiedSlots, capacity: page.gridSize.capacity) {
            target = free
        } else {
            return nil
        }

        let pictogram = Pictogram(label: label, spokenText: spokenText, imageData: imageData, recordingData: recordingData, source: source)
        pictogram.sourceRef = sourceRef
        pictogram.licence = licence
        pictogram.wordType = wordType
        context.insert(pictogram)
        let placement = Placement(slot: target)
        context.insert(placement)
        placement.page = page
        placement.pictogram = pictogram
        return placement
    }

    /// Drops a placement on a slot. If the slot is taken, the two pictograms swap places,
    /// so every other pictogram stays where the child expects it.
    @discardableResult
    func move(_ placement: Placement, to page: Page, slot: Int) -> Bool {
        guard page.gridSize.contains(slot) else { return false }
        let sourcePage = placement.page
        let sourceSlot = placement.slot
        if sourcePage?.id == page.id, sourceSlot == slot { return true }

        if let occupant = page.placement(at: slot), occupant.id != placement.id {
            occupant.page = sourcePage
            occupant.slot = sourceSlot
        }
        placement.page = page
        placement.slot = slot
        save()
        return true
    }

    /// Moves a placement to the first free slot of another page. Returns false when that page is full.
    @discardableResult
    func move(_ placement: Placement, toPage page: Page) -> Bool {
        if placement.page?.id == page.id { return true }
        guard let slot = GridMath.firstFreeSlot(occupied: page.occupiedSlots, capacity: page.gridSize.capacity) else {
            return false
        }
        return move(placement, to: page, slot: slot)
    }

    /// Places the same pictogram on another page too. Returns false when that page is full.
    @discardableResult
    func duplicate(_ placement: Placement, toPage page: Page) -> Bool {
        guard let pictogram = placement.pictogram,
              let slot = GridMath.firstFreeSlot(occupied: page.occupiedSlots, capacity: page.gridSize.capacity)
        else { return false }
        let copy = Placement(slot: slot)
        context.insert(copy)
        copy.page = page
        copy.pictogram = pictogram
        save()
        return true
    }

    func setHidden(_ placement: Placement, _ hidden: Bool) {
        placement.isHidden = hidden
        save()
    }

    /// Removes a placement. The pictogram is deleted too when it is not placed anywhere else.
    func remove(_ placement: Placement) {
        removeWithoutSaving(placement)
        save()
    }

    private func removeWithoutSaving(_ placement: Placement) {
        let pictogram = placement.pictogram
        let isLastPlacement = (pictogram?.placements ?? []).allSatisfy { $0.id == placement.id }
        context.delete(placement)
        if let pictogram, isLastPlacement {
            context.delete(pictogram)
        }
    }

    // MARK: Reset

    /// Deletes every page, placement and pictogram. With iCloud, the deletion reaches the other devices.
    func deleteAllContent() {
        for page in allPages() {
            for placement in page.placements ?? [] {
                removeWithoutSaving(placement)
            }
            context.delete(page)
        }
        // Pictograms that were not placed anywhere.
        for pictogram in (try? context.fetch(FetchDescriptor<Pictogram>())) ?? [] {
            context.delete(pictogram)
        }
        save()
    }

    // MARK: Starter content

    /// The minimal content: a page "Mes choses" with 4 empty slots, a page "Cartes critiques"
    /// (Non, Oui, Attends, Fini, Encore, Pause) and the permanent bar with the three actions
    /// Aide, Je veux and Ouvre, which open the sentence bar.
    /// Safe to call several times: it only creates what is missing.
    func seedStarterContent() {
        let kit = StarterKit.load()
        if normalPages().isEmpty {
            addPage(title: "Mes choses", columns: 2, rows: 2)
            if let kit, let critical = kit.page(titled: "Cartes critiques") {
                let page = addPage(title: critical.title, columns: critical.columns, rows: critical.rows)
                for (index, item) in critical.items.enumerated() {
                    insert(item, from: kit, on: page, slot: index)
                }
            }
        }
        if permanentBar() == nil {
            let bar = Page(title: "Barre permanente", columns: 3, rows: 1, sortIndex: 0, kind: .permanentBar)
            context.insert(bar)
            insertAction(label: "Aide", spoken: "J'ai besoin d'aide", fallbackSymbol: "person.fill.questionmark", tint: .systemBlue, kit: kit, on: bar, slot: 0)
            insertAction(label: "Je veux", spoken: "Je veux", fallbackSymbol: "hand.point.right.fill", tint: .systemOrange, kit: kit, on: bar, slot: 1)
            insertAction(label: "Ouvre", spoken: "Ouvre", fallbackSymbol: "door.left.hand.open", tint: .systemGreen, kit: kit, on: bar, slot: 2)
        }
        save()
    }

    /// A sentence starter for the permanent bar: the ARASAAC card from the kit when it is bundled,
    /// otherwise a simple SF Symbol card.
    private func insertAction(label: String, spoken: String, fallbackSymbol: String, tint: UIColor, kit: StarterKit?, on bar: Page, slot: Int) {
        if let kit, let item = kit.barItem(labelled: label), let image = kit.imageData(for: item) {
            insertPictogram(
                label: item.label, spokenText: item.spoken ?? spoken, imageData: image, recordingData: nil,
                source: .arasaac, sourceRef: String(item.arasaac), licence: ArasaacAPI.licence, wordType: .starter, on: bar, slot: slot
            )
        } else {
            insertPictogram(
                label: label, spokenText: spoken, imageData: ImageTools.symbolCard(systemName: fallbackSymbol, tint: tint),
                recordingData: nil, source: .symbol, sourceRef: nil, licence: nil, wordType: .starter, on: bar, slot: slot
            )
        }
    }

    /// Adds the starter kit: the actions on the permanent bar and one page per theme.
    /// Safe to call several times: cards already on the bar (same label) and pages with the same
    /// title are left alone. Returns the number of pictograms added.
    @discardableResult
    func installStarterKit(_ kit: StarterKit) -> Int {
        var added = 0

        // Permanent bar: add the actions that are missing.
        let bar: Page
        if let existing = permanentBar() {
            bar = existing
        } else {
            bar = Page(title: "Barre permanente", columns: kit.bar.columns, rows: kit.bar.rows, sortIndex: 0, kind: .permanentBar)
            context.insert(bar)
        }
        let barLabels = Set((bar.placements ?? []).compactMap { $0.pictogram?.label.lowercased() })
        let missing = kit.bar.items.filter { !barLabels.contains($0.label.lowercased()) }
        let needed = bar.occupiedSlots.count + missing.count
        if needed > bar.gridSize.capacity {
            let columns = min(needed, GridSize.columnRange.upperBound)
            let rows = Int((Double(needed) / Double(columns)).rounded(.up))
            resize(bar, columns: columns, rows: rows)
        }
        for item in missing {
            if insert(item, from: kit, on: bar, slot: nil) { added += 1 }
        }

        // Theme pages.
        let titles = Set(normalPages().map { $0.title.lowercased() })
        for kitPage in kit.pages where !titles.contains(kitPage.title.lowercased()) {
            let page = addPage(title: kitPage.title, columns: kitPage.columns, rows: kitPage.rows)
            for (index, item) in kitPage.items.enumerated() {
                if insert(item, from: kit, on: page, slot: index) { added += 1 }
            }
        }

        upgradeStarters(using: kit)
        save()
        return added
    }

    @discardableResult
    private func insert(_ item: StarterKit.Item, from kit: StarterKit, on page: Page, slot: Int?) -> Bool {
        guard let image = kit.imageData(for: item) else { return false }
        return insertPictogram(
            label: item.label, spokenText: item.spoken, imageData: image, recordingData: nil,
            source: .arasaac, sourceRef: String(item.arasaac), licence: ArasaacAPI.licence, wordType: item.wordType, on: page, slot: slot
        ) != nil
    }

    /// Marks existing cards that match a starter of the kit (same ARASAAC id, or same label) as
    /// sentence starters, for content created before the sentence bar existed. Never downgrades a card.
    /// Returns the number of cards changed.
    @discardableResult
    func upgradeStarters(using kit: StarterKit) -> Int {
        let refs = kit.starterSourceRefs
        let labels = kit.starterLabels
        let pictograms = (try? context.fetch(FetchDescriptor<Pictogram>())) ?? []
        var changed = 0
        for pictogram in pictograms where !pictogram.isSentenceStarter {
            let byRef = pictogram.source == .arasaac && pictogram.sourceRef.map(refs.contains) == true
            let byLabel = labels.contains(pictogram.label.trimmingCharacters(in: .whitespaces).lowercased())
            if byRef || byLabel {
                pictogram.wordType = .starter
                changed += 1
            }
        }
        if changed > 0 { save() }
        return changed
    }

    func save() {
        do {
            try context.save()
        } catch {
            print("Save failed: \(error)")
        }
    }
}
