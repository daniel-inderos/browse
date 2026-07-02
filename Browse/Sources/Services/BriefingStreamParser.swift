import Foundation

/// Parses the (possibly still-streaming) structured-output JSON of a briefing
/// into display fields, preserving section identity across re-parses so
/// SwiftUI doesn't treat every streaming update as a remove+insert.
struct BriefingStreamParser {
    struct Result {
        var headline: String
        var tldr: String
        var sections: [BriefingSection]
    }

    static func parse(_ rawJSON: String, existingSections: [BriefingSection]) -> Result? {
        guard let value = PartialJSONParser.parse(rawJSON) else { return nil }

        let headline = value["headline"]?.stringValue ?? ""
        let tldr = value["tldr"]?.stringValue ?? ""

        var sections: [BriefingSection] = []
        for entry in value["sections"]?.arrayValue ?? [] {
            guard let title = entry["title"]?.stringValue else { continue }
            let content = entry["content"]?.stringValue ?? ""
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            sections.append(BriefingSection(title: title, content: content))
        }

        for i in sections.indices {
            if i < existingSections.count, existingSections[i].title == sections[i].title {
                sections[i] = BriefingSection(
                    id: existingSections[i].id,
                    title: sections[i].title,
                    content: sections[i].content
                )
            }
        }

        return Result(headline: headline, tldr: tldr, sections: sections)
    }
}
