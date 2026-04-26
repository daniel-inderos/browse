import SwiftUI

struct IntentSuggestion: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case briefingQuery
        case openTab
        case frequentDomain
        case searchAutocomplete
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    let fillText: String
    let tabID: UUID?

    init(
        kind: Kind,
        title: String,
        subtitle: String? = nil,
        fillText: String,
        tabID: UUID? = nil
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.fillText = fillText
        self.tabID = tabID
        self.id = "\(kind.rawValue)::\(fillText.lowercased())"
    }
}

struct IntentSuggestionSection: Identifiable, Hashable {
    let id: String
    let title: String
    let suggestions: [IntentSuggestion]

    init(title: String, suggestions: [IntentSuggestion]) {
        self.title = title
        self.suggestions = suggestions
        self.id = title.lowercased()
    }
}

struct IntentBarSuggestions: View {
    let sections: [IntentSuggestionSection]
    let highlightedSuggestionID: String?
    let onSelect: (IntentSuggestion) -> Void

    @State private var hoveredIndex: Int?

    var body: some View {
        if !sections.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.offset) { sectionIndex, section in
                    if sectionIndex > 0 {
                        Divider()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }

                    Text(section.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    ForEach(Array(section.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        let rowIndex = rowIndexFor(sectionIndex: sectionIndex, itemIndex: index)
                        Button(action: { onSelect(suggestion) }) {
                            HStack(spacing: 8) {
                                Image(systemName: iconName(for: suggestion.kind))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.tertiary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                        .font(BrowseFont.intentBar)
                                        .foregroundStyle(.primary)

                                    if let subtitle = suggestion.subtitle {
                                        Text(subtitle)
                                            .font(.system(size: 11, weight: .regular))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                hoveredIndex == rowIndex || highlightedSuggestionID == suggestion.id
                                    ? BrowseColor.surfaceHover
                                    : Color.clear
                            )
                        }
                        .buttonStyle(.plain)
                        .onHover { isHovering in
                            hoveredIndex = isHovering ? rowIndex : nil
                        }

                        if index < section.suggestions.count - 1 {
                            Divider()
                                .padding(.horizontal, 12)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(BrowseColor.borderSubtle, lineWidth: 0.5)
            )
            .warmShadow(radius: 12, y: 4)
        }
    }

    private func iconName(for kind: IntentSuggestion.Kind) -> String {
        switch kind {
        case .briefingQuery:
            return "doc.text.magnifyingglass"
        case .openTab:
            return "safari"
        case .frequentDomain:
            return "globe"
        case .searchAutocomplete:
            return "magnifyingglass"
        }
    }

    private func rowIndexFor(sectionIndex: Int, itemIndex: Int) -> Int {
        let priorCount = sections
            .prefix(sectionIndex)
            .reduce(0) { $0 + $1.suggestions.count }
        return priorCount + itemIndex
    }
}
