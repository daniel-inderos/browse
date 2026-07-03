import Foundation
import Testing
@testable import Browse

@Suite("BriefingStreamParser")
struct BriefingStreamParserTests {
    private let fullPayload = #"""
    {"headline": "Passkeys Reach Mainstream Adoption", "tldr": "Most major platforms now default to passkeys.", "sections": [{"title": "Adoption", "content": "Adoption grew [[1]](cite://1)."}, {"title": "Key Takeaways", "content": "- Passkeys are the default [[2]](cite://2)"}]}
    """#

    @Test("Parses a complete briefing payload")
    func parsesCompletePayload() {
        let result = BriefingStreamParser.parse(fullPayload, existingSections: [])

        #expect(result?.headline == "Passkeys Reach Mainstream Adoption")
        #expect(result?.tldr == "Most major platforms now default to passkeys.")
        #expect(result?.sections.count == 2)
        #expect(result?.sections[0].title == "Adoption")
        #expect(result?.sections[1].content.contains("cite://2") == true)
    }

    @Test("Streaming prefixes surface fields as they arrive")
    func parsesStreamingPrefixes() {
        let midHeadline = String(fullPayload.prefix(30))
        let early = BriefingStreamParser.parse(midHeadline, existingSections: [])
        #expect(early?.headline.hasPrefix("Passkeys") == true)
        #expect(early?.sections.isEmpty == true)

        let midSection = String(fullPayload.prefix(200))
        let later = BriefingStreamParser.parse(midSection, existingSections: [])
        #expect(later?.headline == "Passkeys Reach Mainstream Adoption")
        #expect(later?.sections.count == 1)
    }

    @Test("Preserves section identity across re-parses")
    func preservesSectionIdentity() throws {
        let first = BriefingStreamParser.parse(
            String(fullPayload.prefix(200)),
            existingSections: []
        )
        let firstSections = try #require(first?.sections)

        let second = BriefingStreamParser.parse(fullPayload, existingSections: firstSections)
        let secondSections = try #require(second?.sections)

        #expect(secondSections[0].id == firstSections[0].id)
        #expect(secondSections.count == 2)
    }

    @Test("Skips sections whose content has not started streaming")
    func skipsEmptySections() {
        let partial = #"{"headline": "H", "tldr": "T", "sections": [{"title": "One", "content": ""#
        let result = BriefingStreamParser.parse(partial, existingSections: [])

        #expect(result?.sections.isEmpty == true)
    }

    @Test("Non-JSON input yields nil")
    func nonJSONInput() {
        #expect(BriefingStreamParser.parse("# Old markdown briefing", existingSections: []) == nil)
    }
}
