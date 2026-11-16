import Foundation
import PictoCore

/// The bundled starter kit (*kit de démarrage*): ARASAAC pictograms for the first vocabulary,
/// described in `Resources/StarterKit/StarterKit.json` with one `arasaac-<id>.png` per item.
struct StarterKit: Decodable {
    struct Item: Decodable {
        let label: String
        let spoken: String?
        /// ARASAAC pictogram id, also the image file name (`arasaac-<id>.png`).
        let arasaac: Int
        /// Opens the sentence bar ("Je veux", "Ouvre"…).
        let starter: Bool?

        var imageName: String { "arasaac-\(arasaac)" }
        var isStarter: Bool { starter ?? false }
        var wordType: WordType { isStarter ? .starter : .noun }
    }

    struct KitPage: Decodable {
        let title: String
        let columns: Int
        let rows: Int
        let items: [Item]
    }

    let version: Int
    /// The critical cards, placed on the permanent bar.
    let bar: KitPage
    let pages: [KitPage]

    var allItems: [Item] { bar.items + pages.flatMap(\.items) }
    var pictogramCount: Int { allItems.count }

    /// ARASAAC ids of the starters, as stored in `Pictogram.sourceRef`.
    var starterSourceRefs: Set<String> { Set(allItems.filter(\.isStarter).map { String($0.arasaac) }) }
    /// Lower-cased labels of the starters.
    var starterLabels: Set<String> { Set(allItems.filter(\.isStarter).map { $0.label.lowercased() }) }

    func page(titled title: String) -> KitPage? {
        pages.first { $0.title.caseInsensitiveCompare(title) == .orderedSame }
    }

    func barItem(labelled label: String) -> Item? {
        bar.items.first { $0.label.caseInsensitiveCompare(label) == .orderedSame }
    }

    // MARK: Loading

    static func load(from bundle: Bundle = .main) -> StarterKit? {
        guard let url = resourceURL("StarterKit", "json", in: bundle),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(StarterKit.self, from: data)
    }

    func imageData(for item: Item, in bundle: Bundle = .main) -> Data? {
        guard let url = Self.resourceURL(item.imageName, "png", in: bundle) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Looks in the `StarterKit` folder first, then at the bundle root (Xcode flattens synchronized groups).
    private static func resourceURL(_ name: String, _ ext: String, in bundle: Bundle) -> URL? {
        bundle.url(forResource: name, withExtension: ext, subdirectory: "StarterKit")
            ?? bundle.url(forResource: name, withExtension: ext)
    }
}
