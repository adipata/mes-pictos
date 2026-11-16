import Foundation

/// A pictogram as returned by the ARASAAC search API, reduced to what the app needs.
public struct ArasaacPictogram: Decodable, Identifiable, Hashable, Sendable {
    public let id: Int
    /// French keywords, the first one is the main word.
    public let keywords: [String]

    public init(id: Int, keywords: [String]) {
        self.id = id
        self.keywords = keywords
    }

    public var title: String { keywords.first ?? "#\(id)" }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case keywords
    }

    private struct Keyword: Decodable {
        let keyword: String?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        let raw = try container.decodeIfPresent([Keyword].self, forKey: .keywords) ?? []
        keywords = raw.compactMap(\.keyword).filter { !$0.isEmpty }
    }
}

/// URLs and texts for the ARASAAC library (https://arasaac.org), French edition.
public enum ArasaacAPI {
    public static let locale = "fr"
    public static let website = URL(string: "https://arasaac.org")!
    /// Stored in `Pictogram.licence` for every ARASAAC image.
    public static let licence = "CC BY-NC-SA – ARASAAC"
    /// Attribution required by the licence, shown on the credits screen and in the search.
    public static let attribution = "Les symboles pictographiques utilisés sont la propriété du Gouvernement d'Aragon et ont été créés par Sergio Palao pour ARASAAC (https://arasaac.org), qui les distribue sous licence Creative Commons BY-NC-SA."

    /// Keyword search. The API answers 404 when nothing matches.
    public static func searchURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "https://api.arasaac.org/v1/pictograms/\(locale)/search/\(encoded)")
    }

    /// Static PNG of a pictogram. Resolutions available: 300, 500, 2500.
    public static func imageURL(id: Int, resolution: Int = 500) -> URL {
        URL(string: "https://static.arasaac.org/pictograms/\(id)/\(id)_\(resolution).png")!
    }

    public static func decodeSearch(_ data: Data) throws -> [ArasaacPictogram] {
        try JSONDecoder().decode([ArasaacPictogram].self, from: data)
    }
}
