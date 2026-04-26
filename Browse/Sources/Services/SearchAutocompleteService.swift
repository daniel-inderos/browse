import Foundation

final class SearchAutocompleteService: Sendable {
    private let session: URLSession
    private let baseURL: URL

    init(
        session: URLSession? = nil,
        baseURL: URL = URL(string: "https://suggestqueries.google.com/complete/search")!
    ) {
        self.session = session ?? URLSession(configuration: .ephemeral)
        self.baseURL = baseURL
    }

    func suggestions(for query: String, limit: Int = 5) async throws -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        guard let request = Self.request(for: trimmed, baseURL: baseURL) else { return [] }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return []
        }

        return try Self.parseSuggestions(from: data, excluding: trimmed, limit: limit)
    }

    static func request(for query: String, baseURL: URL) -> URLRequest? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client", value: "firefox"),
            URLQueryItem(name: "q", value: query)
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 6
        return request
    }

    static func parseSuggestions(
        from data: Data,
        excluding query: String? = nil,
        limit: Int = 5
    ) throws -> [String] {
        let response = try JSONDecoder().decode(GoogleAutocompleteResponse.self, from: data)
        let excludedQuery = query?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        var seen = Set<String>()
        var suggestions: [String] = []

        for phrase in response.suggestions {
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !trimmed.isEmpty else { continue }
            guard key != excludedQuery else { continue }
            guard seen.insert(key).inserted else { continue }

            suggestions.append(trimmed)
            if suggestions.count >= limit { break }
        }

        return suggestions
    }
}

private struct GoogleAutocompleteResponse: Decodable {
    let suggestions: [String]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        _ = try container.decode(String.self)
        suggestions = try container.decode([String].self)
    }
}
