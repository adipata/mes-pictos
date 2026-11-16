import Foundation
import PictoCore

enum ArasaacError: LocalizedError {
    case offline
    case server(Int)
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .offline: return "Pas de connexion Internet. La recherche ARASAAC a besoin d'Internet ; les pictogrammes déjà ajoutés fonctionnent hors ligne."
        case .server(let code): return "ARASAAC ne répond pas (erreur \(code)). Réessayez dans un moment."
        case .invalidImage: return "L'image n'a pas pu être lue."
        }
    }
}

/// Searches the ARASAAC library and downloads pictograms. Results are cached for the app's lifetime.
actor ArasaacClient {
    static let shared = ArasaacClient()

    private let session: URLSession
    private var searchCache: [String: [ArasaacPictogram]] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// French keyword search. An empty result is not an error.
    func search(_ text: String) async throws -> [ArasaacPictogram] {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let cached = searchCache[key] { return cached }
        guard let url = ArasaacAPI.searchURL(key) else { return [] }

        let (data, response) = try await perform(url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return [] }
        guard (200..<300).contains(status) else { throw ArasaacError.server(status) }

        let results = try ArasaacAPI.decodeSearch(data)
        searchCache[key] = results
        return results
    }

    /// The 500 px PNG of a pictogram, ready to be stored in a `Pictogram`.
    func image(id: Int) async throws -> Data {
        let (data, response) = try await perform(ArasaacAPI.imageURL(id: id))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ArasaacError.server(status) }
        guard data.count > 100 else { throw ArasaacError.invalidImage }
        return data
    }

    private func perform(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("MesPictos/1.0", forHTTPHeaderField: "User-Agent")
        do {
            return try await session.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .timedOut, .dataNotAllowed].contains(error.code) {
            throw ArasaacError.offline
        }
    }
}
