import Foundation

struct BriefingDocument: Codable {
    let id: UUID
    let query: String
    var headline: String
    var tldr: String
    var sections: [BriefingSection]
    var sources: [Source]
    var followUpSuggestions: [String]
    var isStreaming: Bool
    var streamedMarkdown: String

    init(query: String) {
        self.id = UUID()
        self.query = query
        self.headline = ""
        self.tldr = ""
        self.sections = []
        self.sources = []
        self.followUpSuggestions = []
        self.isStreaming = false
        self.streamedMarkdown = ""
    }

    /// Markdown representation of the parsed briefing, used as context for
    /// follow-up prompts and chat tab mentions. `streamedMarkdown` holds the
    /// raw model output (JSON for briefings generated via structured outputs,
    /// markdown for documents persisted by older versions), so it is only
    /// used as a fallback when no parsed fields are available.
    var renderedMarkdown: String {
        guard !headline.isEmpty || !sections.isEmpty else {
            return streamedMarkdown
        }
        var parts: [String] = []
        if !headline.isEmpty {
            parts.append("# \(headline)")
        }
        if !tldr.isEmpty {
            parts.append("**TL;DR:** \(tldr)")
        }
        for section in sections {
            parts.append("## \(section.title)\n\(section.content)")
        }
        return parts.joined(separator: "\n\n")
    }
}

struct BriefingSection: Identifiable, Codable {
    let id: UUID
    var title: String
    var content: String

    init(title: String, content: String) {
        self.id = UUID()
        self.title = title
        self.content = content
    }

    /// Preserves an existing identity (used during incremental re-parsing).
    init(id: UUID, title: String, content: String) {
        self.id = id
        self.title = title
        self.content = content
    }
}
