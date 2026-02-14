import SwiftUI

struct BriefingSourceShelf: View {
    let sources: [Source]
    let onSourceTap: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                        SourceCard(index: index + 1, source: source)
                            .onTapGesture { onSourceTap(source.url) }
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 1) // Prevent clipping of card borders
            }
        }
    }
}

// MARK: - Source Card

struct SourceCard: View {
    let index: Int
    let source: Source

    @State private var isHovering = false

    private let cardWidth: CGFloat = 234
    private let cardHeight: CGFloat = 128

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row: index + domain
            HStack(spacing: 6) {
                // Citation number badge
                Text("\(index)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(BrowseColor.accent.opacity(0.7), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

                FaviconView(url: source.faviconURL ?? source.url, size: 12)

                Text(source.url.host ?? "")
                    .font(BrowseFont.sourceDomain)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            // Title
            Text(source.title)
                .font(BrowseFont.sourceTitle)
                .lineLimit(2)
                .foregroundStyle(.primary)

            // Snippet
            if !source.snippet.isEmpty {
                Text(source.snippet)
                    .font(BrowseFont.sourceDomain)
                    .foregroundStyle(.quaternary)
                    .lineLimit(2)
            } else {
                // Keep cards visually uniform even when snippet is missing.
                Text(" ")
                    .font(BrowseFont.sourceDomain)
                    .lineLimit(2)
                    .hidden()
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovering ? BrowseColor.surfaceHover : BrowseColor.surfaceSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isHovering ? BrowseColor.accent.opacity(0.15) : BrowseColor.borderSubtle,
                    lineWidth: 0.5
                )
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .contentShape(Rectangle())
    }
}
