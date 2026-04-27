import Foundation

enum ExaAPIError: Error, LocalizedError {
    case noAPIKey
    case httpError(statusCode: Int, body: String)
    case decodingError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "Exa API key not configured. Add EXA_API_KEY to .env."
        case .httpError(let code, _): "HTTP \(code)"
        case .decodingError: "Decoding error"
        case .networkError: "Network error"
        }
    }
}

final class ExaAPIClient: Sendable {
    private let getAPIKey: @Sendable () -> String?
    private let session: URLSession
    private let baseURL = URL(string: "https://api.exa.ai/search")!

    init(getAPIKey: @escaping @Sendable () -> String?, session: URLSession = .shared) {
        self.getAPIKey = getAPIKey
        self.session = session
    }

    func search(
        query: String,
        numResults: Int = 8,
        includeText: Bool = true
    ) async throws -> ExaSearchResponse {
        guard let apiKey = getAPIKey() else {
            throw ExaAPIError.noAPIKey
        }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let body = ExaSearchRequest(
            query: query,
            type: "auto",
            numResults: numResults,
            contents: includeText ? ExaContents(
                text: ExaTextConfig(maxCharacters: 8000),
                highlights: ExaHighlightsConfig(numSentences: 3, highlightsPerUrl: 2)
            ) : nil
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExaAPIError.networkError(
                NSError(domain: "ExaAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            )
        }

        guard httpResponse.statusCode == 200 else {
            throw ExaAPIError.httpError(
                statusCode: httpResponse.statusCode,
                body: "redacted \(data.count) bytes"
            )
        }

        do {
            return try JSONDecoder().decode(ExaSearchResponse.self, from: data)
        } catch {
            throw ExaAPIError.decodingError(error.localizedDescription)
        }
    }

    func testConnection() async throws -> Bool {
        guard let apiKey = getAPIKey() else {
            throw ExaAPIError.noAPIKey
        }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let body = ExaSearchRequest(
            query: "test",
            type: "fast",
            numResults: 1,
            contents: nil
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }
}
