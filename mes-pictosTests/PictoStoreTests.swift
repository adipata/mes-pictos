import XCTest
import SwiftData
@testable import MesPictos

@MainActor
final class PictoStoreTests: XCTestCase {
    private var container: ModelContainer?

    private func makeStore() -> PictoStore {
        let container = Persistence.makeInMemoryContainer()
        self.container = container
        return PictoStore(context: container.mainContext)
    }

    private func card(_ label: String, on page: Page, slot: Int? = nil, in store: PictoStore) -> Placement {
        guard let placement = store.createPictogram(label: label, on: page, slot: slot) else {
            XCTFail("Could not create \(label)")
            fatalError()
        }
        return placement
    }

    private func label(at slot: Int, of page: Page) -> String? {
        page.placement(at: slot)?.pictogram?.label
    }

    func testCreateUsesRequestedSlotOrFirstFree() {
        let store = makeStore()
        let page = store.addPage(title: "Manger", columns: 2, rows: 2)
        _ = card("pomme", on: page, slot: 3, in: store)
        _ = card("lait", on: page, in: store)
        XCTAssertEqual(label(at: 3, of: page), "pomme")
        XCTAssertEqual(label(at: 0, of: page), "lait")
    }

    func testCreateFailsOnFullPage() {
        let store = makeStore()
        let page = store.addPage(title: "Une", columns: 1, rows: 1)
        _ = card("pomme", on: page, in: store)
        XCTAssertNil(store.createPictogram(label: "lait", on: page))
    }

    func testMoveToEmptySlot() {
        let store = makeStore()
        let page = store.addPage(title: "Manger", columns: 2, rows: 2)
        let apple = card("pomme", on: page, slot: 0, in: store)
        XCTAssertTrue(store.move(apple, to: page, slot: 2))
        XCTAssertNil(page.placement(at: 0))
        XCTAssertEqual(label(at: 2, of: page), "pomme")
    }

    func testDropOnOccupiedSlotSwaps() {
        let store = makeStore()
        let page = store.addPage(title: "Manger", columns: 2, rows: 2)
        let apple = card("pomme", on: page, slot: 0, in: store)
        _ = card("lait", on: page, slot: 1, in: store)
        _ = card("pain", on: page, slot: 3, in: store)

        XCTAssertTrue(store.move(apple, to: page, slot: 1))

        XCTAssertEqual(label(at: 0, of: page), "lait")
        XCTAssertEqual(label(at: 1, of: page), "pomme")
        XCTAssertEqual(label(at: 3, of: page), "pain", "Other cards keep their place")
    }

    func testMoveAcrossPagesSwapsWithOccupant() {
        let store = makeStore()
        let food = store.addPage(title: "Manger", columns: 2, rows: 1)
        let toys = store.addPage(title: "Jouer", columns: 2, rows: 1)
        let apple = card("pomme", on: food, slot: 0, in: store)
        _ = card("ballon", on: toys, slot: 1, in: store)

        XCTAssertTrue(store.move(apple, to: toys, slot: 1))

        XCTAssertEqual(label(at: 1, of: toys), "pomme")
        XCTAssertEqual(label(at: 0, of: food), "ballon")
    }

    func testMoveToPageUsesFirstFreeSlotAndFailsWhenFull() {
        let store = makeStore()
        let food = store.addPage(title: "Manger", columns: 2, rows: 1)
        let toys = store.addPage(title: "Jouer", columns: 2, rows: 1)
        let apple = card("pomme", on: food, in: store)
        let milk = card("lait", on: food, in: store)
        _ = card("ballon", on: toys, slot: 0, in: store)

        XCTAssertTrue(store.move(apple, toPage: toys))
        XCTAssertEqual(label(at: 1, of: toys), "pomme")
        XCTAssertFalse(store.move(milk, toPage: toys), "Toys page is full")
        XCTAssertEqual(milk.page?.id, food.id)
    }

    func testDuplicateKeepsOnePictogram() {
        let store = makeStore()
        let food = store.addPage(title: "Manger", columns: 2, rows: 1)
        let toys = store.addPage(title: "Jouer", columns: 2, rows: 1)
        let apple = card("pomme", on: food, in: store)

        XCTAssertTrue(store.duplicate(apple, toPage: toys))
        XCTAssertEqual(toys.placement(at: 0)?.pictogram?.id, apple.pictogram?.id)

        // Removing one placement keeps the pictogram for the other page.
        store.remove(apple)
        XCTAssertEqual(label(at: 0, of: toys), "pomme")
        let pictograms = (try? store.context.fetch(FetchDescriptor<Pictogram>())) ?? []
        XCTAssertEqual(pictograms.count, 1)
    }

    func testRemovingLastPlacementDeletesPictogram() {
        let store = makeStore()
        let page = store.addPage(title: "Manger")
        let apple = card("pomme", on: page, in: store)
        store.remove(apple)
        let pictograms = (try? store.context.fetch(FetchDescriptor<Pictogram>())) ?? []
        XCTAssertTrue(pictograms.isEmpty)
        XCTAssertNil(page.placement(at: 0))
    }

    func testResizeKeepsVisualPositions() {
        let store = makeStore()
        let page = store.addPage(title: "Manger", columns: 2, rows: 2)
        _ = card("pomme", on: page, slot: 0, in: store)
        _ = card("pain", on: page, slot: 3, in: store) // row 1, column 1

        XCTAssertTrue(store.resize(page, columns: 3, rows: 2))

        XCTAssertEqual(page.columns, 3)
        XCTAssertEqual(label(at: 0, of: page), "pomme")
        XCTAssertEqual(label(at: 4, of: page), "pain") // still row 1, column 1
    }

    func testResizeRefusesTooSmallGrid() {
        let store = makeStore()
        let page = store.addPage(title: "Manger", columns: 2, rows: 1)
        _ = card("pomme", on: page, in: store)
        _ = card("lait", on: page, in: store)
        XCTAssertFalse(store.resize(page, columns: 1, rows: 1))
        XCTAssertEqual(page.columns, 2)
    }

    func testMovePageOrder() {
        let store = makeStore()
        let first = store.addPage(title: "A")
        let second = store.addPage(title: "B")
        store.movePage(second, by: -1)
        XCTAssertEqual(store.normalPages().map(\.title), ["B", "A"])
        store.movePage(first, by: -1)
        XCTAssertEqual(store.normalPages().map(\.title), ["A", "B"])
    }

    func testNewPagesGetDifferentColoursAndFirstCardAsIcon() {
        let store = makeStore()
        var colours: [PageColor] = []
        for index in 0..<4 {
            let page = store.addPage(title: "Page \(index)")
            colours.append(try! XCTUnwrap(page.color))
        }
        XCTAssertEqual(Set(colours).count, 4, "Neighbouring tabs have different colours")

        let page = store.normalPages()[0]
        XCTAssertNil(page.iconPictogram, "No card yet")
        let apple = card("pomme", on: page, slot: 2, in: store)
        let milk = card("lait", on: page, slot: 0, in: store)
        XCTAssertEqual(page.iconPictogram?.label, "lait", "The first card in slot order")
        store.setHidden(milk, true)
        XCTAssertEqual(page.iconPictogram?.label, "pomme", "Hidden cards are skipped")

        page.iconPictogramID = apple.pictogram?.id
        XCTAssertEqual(page.iconPictogram?.label, "pomme")
        store.remove(apple)
        XCTAssertNil(page.iconPictogram, "A removed icon card falls back to the first visible card")
        XCTAssertEqual(Page(title: "old", columns: 2, rows: 2, sortIndex: 3).tabColor(atIndex: 3), PageColor.automatic(forIndex: 3))
    }

    func testDeletePageRemovesItsPictograms() {
        let store = makeStore()
        let page = store.addPage(title: "Manger")
        _ = card("pomme", on: page, in: store)
        store.delete(page)
        XCTAssertTrue(store.normalPages().isEmpty)
        let pictograms = (try? store.context.fetch(FetchDescriptor<Pictogram>())) ?? []
        XCTAssertTrue(pictograms.isEmpty)
    }

    func testDeleteAllContentEmptiesTheStore() {
        let store = makeStore()
        store.seedStarterContent()
        let orphan = Pictogram(label: "seul")
        store.context.insert(orphan)
        store.save()

        store.deleteAllContent()

        XCTAssertTrue(store.allPages().isEmpty)
        XCTAssertNil(store.permanentBar())
        XCTAssertEqual(((try? store.context.fetch(FetchDescriptor<Pictogram>())) ?? []).count, 0)
        XCTAssertEqual(((try? store.context.fetch(FetchDescriptor<Placement>())) ?? []).count, 0)
    }

    func testSettingsReset() {
        let defaults = UserDefaults(suiteName: "reset-test")!
        defaults.removePersistentDomain(forName: "reset-test")
        defaults.set(true, forKey: SettingsKey.onboardingDone)
        defaults.set(0.3, forKey: SettingsKey.speechRate)
        defaults.set("1234", forKey: SettingsKey.parentCode)

        SettingsKey.resetAll(in: defaults)
        XCTAssertNil(defaults.object(forKey: SettingsKey.speechRate))
        XCTAssertNil(defaults.object(forKey: SettingsKey.parentCode))
        XCTAssertEqual(defaults.bool(forKey: SettingsKey.onboardingDone), true, "Settings reset keeps the app configured")

        SettingsKey.resetAll(in: defaults, includingOnboarding: true)
        XCTAssertNil(defaults.object(forKey: SettingsKey.onboardingDone))
    }

    func testSeedCreatesPageAndBarOnce() {
        let store = makeStore()
        store.seedStarterContent()
        store.seedStarterContent()

        XCTAssertEqual(store.normalPages().map(\.title), ["Mes choses", "Cartes critiques"])
        let bars = store.allPages().filter { $0.kind == .permanentBar }
        XCTAssertEqual(bars.count, 1)
        let bar = try? XCTUnwrap(store.permanentBar())
        XCTAssertEqual(bar.flatMap { label(at: 0, of: $0) }, "Aide")
        XCTAssertEqual(bar.flatMap { label(at: 1, of: $0) }, "Je veux")
        XCTAssertEqual(bar.flatMap { label(at: 2, of: $0) }, "Ouvre")
        XCTAssertEqual(bar?.placement(at: 0)?.pictogram?.spokenText, "J'ai besoin d'aide")
        XCTAssertEqual(bar?.placement(at: 2)?.pictogram?.isSentenceStarter, true)
        XCTAssertNotNil(bar?.placement(at: 0)?.pictogram?.imageData)
    }
}
