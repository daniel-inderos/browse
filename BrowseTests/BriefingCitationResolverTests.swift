import Foundation
import Testing
@testable import Browse

@Suite("BriefingCitationResolver")
struct BriefingCitationResolverTests {
    private let sources = [
        Source(title: "First", url: URL(string: "https://example.com/one")!, snippet: ""),
        Source(title: "Second", url: URL(string: "https://example.com/two")!, snippet: ""),
    ]

    @Test("Resolves standard cite URL host to source URL")
    func resolvesStandardCitationURL() {
        let url = BriefingCitationResolver.sourceURL(
            for: URL(string: "cite://2")!,
            sources: sources
        )

        #expect(url == URL(string: "https://example.com/two")!)
    }

    @Test("Resolves cite URL path fallback to source URL")
    func resolvesPathCitationURL() {
        let url = BriefingCitationResolver.sourceURL(
            for: URL(string: "cite:///1")!,
            sources: sources
        )

        #expect(url == URL(string: "https://example.com/one")!)
    }

    @Test("Ignores out of range citations")
    func ignoresOutOfRangeCitation() {
        let url = BriefingCitationResolver.sourceURL(
            for: URL(string: "cite://8")!,
            sources: sources
        )

        #expect(url == nil)
    }
}
