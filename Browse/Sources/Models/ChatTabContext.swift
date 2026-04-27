import Foundation

struct ChatTabMentionCandidate: Identifiable, Hashable {
    let id: UUID
    let title: String
    let url: URL?
    let kind: TabKind
    let isActive: Bool

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        if let url {
            return url.displayHost
        }

        return "Untitled Tab"
    }

    var displaySubtitle: String {
        switch kind {
        case .web:
            return url?.displayString ?? "Web tab"
        case .briefing:
            return "Briefing"
        }
    }

    var mentionText: String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let normalized = displayTitle
            .unicodeScalars
            .map { allowedCharacters.contains($0) ? Character($0) : "_" }
        let collapsed = String(normalized)
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")

        return "@\(collapsed.isEmpty ? "tab" : collapsed)"
    }
}

struct ChatMentionedTabContext: Identifiable, Hashable {
    let id: UUID
    var title: String
    var url: URL?
    var content: String?

    var label: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        return url?.displayHost ?? "Untitled Tab"
    }
}
