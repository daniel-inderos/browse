import Foundation
import Testing
@testable import Browse

@Suite("SearchAutocompleteService")
struct SearchAutocompleteServiceTests {
    @Test("Request targets Google suggest with Firefox JSON format")
    func requestUsesSuggestEndpoint() throws {
        let baseURL = try #require(URL(string: "https://suggestqueries.google.com/complete/search"))
        let request = try #require(SearchAutocompleteService.request(for: "swift ui", baseURL: baseURL))
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.host == "suggestqueries.google.com")
        #expect(queryValue("client", in: components) == "firefox")
        #expect(queryValue("q", in: components) == "swift ui")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("Parser trims dedupes and excludes current query")
    func parserCleansSuggestions() throws {
        let data = try #require("""
        ["swift",["swift"," swiftui ","swiftui","swift package manager",""]]
        """.data(using: .utf8))

        let suggestions = try SearchAutocompleteService.parseSuggestions(
            from: data,
            excluding: "swift",
            limit: 3
        )

        #expect(suggestions == ["swiftui", "swift package manager"])
    }

    private func queryValue(_ name: String, in components: URLComponents) -> String? {
        components.queryItems?
            .first { $0.name == name }?
            .value
    }
}
