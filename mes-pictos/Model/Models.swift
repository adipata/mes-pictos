import Foundation
import SwiftData
import PictoCore

// CloudKit sync rules, respected by every model:
// no unique attributes, every property optional or with a default, every relationship optional.

enum PageKind: String, Codable {
    case normal
    case permanentBar
}

/// Colour of a page's tab. Child-friendly palette, one colour per page by default.
enum PageColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, teal, blue, purple, pink, brown

    var id: String { rawValue }

    /// Default colour of the page at this position, so neighbouring tabs differ.
    static func automatic(forIndex index: Int) -> PageColor {
        let all = allCases
        return all[((index % all.count) + all.count) % all.count]
    }

    var displayName: String {
        switch self {
        case .red: return "Rouge"
        case .orange: return "Orange"
        case .yellow: return "Jaune"
        case .green: return "Vert"
        case .teal: return "Turquoise"
        case .blue: return "Bleu"
        case .purple: return "Violet"
        case .pink: return "Rose"
        case .brown: return "Marron"
        }
    }
}

/// How a card behaves in a sentence. Stored in `Pictogram.wordTypeRaw`; more types (verb, adjective…) can follow.
enum WordType: String, Codable {
    case noun
    /// Opens the sentence bar: "Je veux", "Ouvre", "J'ai besoin d'aide".
    case starter
}

enum PictogramSource: String, Codable {
    case photo
    case symbol
    case arasaac
    case imported
}

@Model
final class Pictogram {
    var id: UUID = UUID()
    var label: String = ""
    /// Overrides the label for speech, e.g. label "pomme", spoken "une pomme".
    var spokenText: String?
    @Attribute(.externalStorage) var imageData: Data?
    /// Incremented when the image changes, used as image cache key.
    var imageVersion: Int = 0
    /// Parent's recorded voice (AAC). Played instead of text-to-speech.
    @Attribute(.externalStorage) var recordingData: Data?
    var wordTypeRaw: String = "noun"
    var sourceRaw: String = PictogramSource.photo.rawValue
    /// Identifier in the source library, e.g. an ARASAAC id.
    var sourceRef: String?
    var licence: String?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Placement.pictogram)
    var placements: [Placement]? = []

    init(label: String, spokenText: String? = nil, imageData: Data? = nil, recordingData: Data? = nil, source: PictogramSource = .photo) {
        self.id = UUID()
        self.label = label
        self.spokenText = spokenText
        self.imageData = imageData
        self.recordingData = recordingData
        self.sourceRaw = source.rawValue
        self.createdAt = Date()
    }

    var source: PictogramSource {
        get { PictogramSource(rawValue: sourceRaw) ?? .photo }
        set { sourceRaw = newValue.rawValue }
    }

    var wordType: WordType {
        get { WordType(rawValue: wordTypeRaw) ?? .noun }
        set { wordTypeRaw = newValue.rawValue }
    }

    var isSentenceStarter: Bool { wordType == .starter }
}

@Model
final class Page {
    var id: UUID = UUID()
    var title: String = ""
    var sortIndex: Int = 0
    var columns: Int = 2
    var rows: Int = 2
    /// Hidden pages are not shown in child mode.
    var isHidden: Bool = false
    var kindRaw: String = PageKind.normal.rawValue
    var createdAt: Date = Date()
    /// Tab colour. nil for pages created before colours existed: the position decides.
    var colorRaw: String?
    /// Pictogram shown on the tab. nil: the first card of the page.
    var iconPictogramID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \Placement.page)
    var placements: [Placement]? = []

    init(title: String, columns: Int, rows: Int, sortIndex: Int, kind: PageKind = .normal) {
        let size = GridSize(columns: columns, rows: rows)
        self.id = UUID()
        self.title = title
        self.columns = size.columns
        self.rows = size.rows
        self.sortIndex = sortIndex
        self.kindRaw = kind.rawValue
        self.createdAt = Date()
    }

    var kind: PageKind {
        get { PageKind(rawValue: kindRaw) ?? .normal }
        set { kindRaw = newValue.rawValue }
    }

    var gridSize: GridSize { GridSize(columns: columns, rows: rows) }

    var color: PageColor? {
        get { colorRaw.flatMap(PageColor.init(rawValue:)) }
        set { colorRaw = newValue?.rawValue }
    }

    /// The colour shown on the tab: the chosen one, or one from the position of the page.
    func tabColor(atIndex index: Int) -> PageColor {
        color ?? PageColor.automatic(forIndex: index)
    }

    /// Cards in slot order, the ones the child can see.
    var visibleCards: [Pictogram] {
        (placements ?? [])
            .filter { !$0.isHidden && $0.pictogram != nil }
            .sorted { $0.slot < $1.slot }
            .compactMap(\.pictogram)
    }

    /// The pictogram shown on the tab: the chosen one if it is still on the page, otherwise the first card.
    var iconPictogram: Pictogram? {
        if let iconPictogramID, let chosen = visibleCards.first(where: { $0.id == iconPictogramID }) {
            return chosen
        }
        return visibleCards.first
    }

    var displayTitle: String {
        if kind == .permanentBar { return "Barre permanente" }
        return title.isEmpty ? "Sans titre" : title
    }

    /// The placement in a slot. If sync ever produced two, the oldest wins.
    func placement(at slot: Int) -> Placement? {
        (placements ?? [])
            .filter { $0.slot == slot }
            .min { $0.createdAt < $1.createdAt }
    }

    var occupiedSlots: Set<Int> {
        Set((placements ?? []).map(\.slot))
    }

    var hasVisibleCards: Bool {
        (placements ?? []).contains { !$0.isHidden && $0.pictogram != nil }
    }
}

/// A pictogram placed in a slot of a page. The same pictogram can be placed on several pages.
@Model
final class Placement {
    var id: UUID = UUID()
    /// row * columns + column
    var slot: Int = 0
    /// Hidden in child mode, but kept (and shown faded) in parent mode.
    var isHidden: Bool = false
    var createdAt: Date = Date()
    var page: Page?
    var pictogram: Pictogram?

    init(slot: Int) {
        self.id = UUID()
        self.slot = slot
        self.createdAt = Date()
    }
}
