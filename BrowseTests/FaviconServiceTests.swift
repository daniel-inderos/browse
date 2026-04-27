import Foundation
import Testing
@testable import Browse

@Suite("FaviconService")
struct FaviconServiceTests {
    @Test("Page URLs resolve through Google S2 for the page host")
    func pageURLFetchRequest() throws {
        let pageURL = try #require(URL(string: "https://www.example.com/docs"))
        let request = try #require(FaviconService.fetchRequest(for: pageURL))

        #expect(request.cacheKey == "example.com")
        #expect(request.url.host == "www.google.com")
        #expect(queryValue("domain", in: request.url) == "example.com")
        #expect(queryValue("sz", in: request.url) == "64")
    }

    @Test("Private page URLs resolve to first-party favicon root")
    func privatePageURLFetchRequest() throws {
        let pageURL = try #require(URL(string: "https://www.example.com/docs"))
        let request = try #require(FaviconService.fetchRequest(for: pageURL, policy: .firstPartyOnly))

        #expect(request.cacheKey == "https://www.example.com/favicon.ico")
        #expect(request.url.absoluteString == "https://www.example.com/favicon.ico")
        #expect(request.url.host != "www.google.com")
    }

    @Test("Google S2 favicon URLs resolve for their target domain")
    func googleS2FetchRequest() throws {
        let faviconURL = try #require(URL(string: "https://www.google.com/s2/favicons?domain=github.com&sz=32"))
        let request = try #require(FaviconService.fetchRequest(for: faviconURL))

        #expect(request.cacheKey == "github.com")
        #expect(request.url.host == "www.google.com")
        #expect(queryValue("domain", in: request.url) == "github.com")
    }

    @Test("Private Google S2 favicon URLs resolve to first-party favicon root")
    func privateGoogleS2FetchRequest() throws {
        let faviconURL = try #require(URL(string: "https://www.google.com/s2/favicons?domain=github.com&sz=32"))
        let request = try #require(FaviconService.fetchRequest(for: faviconURL, policy: .firstPartyOnly))

        #expect(request.cacheKey == "https://github.com/favicon.ico")
        #expect(request.url.absoluteString == "https://github.com/favicon.ico")
        #expect(request.url.host != "www.google.com")
    }

    @Test("Direct favicon image URLs are fetched directly")
    func directFaviconFetchRequest() throws {
        let faviconURL = try #require(URL(string: "https://cdn.example.com/assets/favicon.ico"))
        let request = try #require(FaviconService.fetchRequest(for: faviconURL))

        #expect(request.cacheKey == faviconURL.absoluteString.lowercased())
        #expect(request.url == faviconURL)
    }

    @Test("Private direct favicon image URLs are still fetched directly")
    func privateDirectFaviconFetchRequest() throws {
        let faviconURL = try #require(URL(string: "https://cdn.example.com/assets/favicon.ico"))
        let request = try #require(FaviconService.fetchRequest(for: faviconURL, policy: .firstPartyOnly))

        #expect(request.cacheKey == faviconURL.absoluteString.lowercased())
        #expect(request.url == faviconURL)
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }
}
