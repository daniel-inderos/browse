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
