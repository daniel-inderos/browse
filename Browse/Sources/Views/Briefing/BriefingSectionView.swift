import SwiftUI
@preconcurrency import MarkdownUI

struct BriefingSectionView: View {
    let section: BriefingSection
    let sources: [Source]
    let onSourceTap: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section title with subtle accent underline
            VStack(alignment: .leading, spacing: 6) {
                Text(section.title)
                    .font(BrowseFont.briefingSectionTitle)
                    .foregroundStyle(.primary)

                RoundedRectangle(cornerRadius: 1)
                    .fill(BrowseColor.accent.opacity(0.2))
                    .frame(width: 28, height: 2)
            }

            // Markdown body
            Markdown(processedContent)
                .markdownTheme(.browseEditorial)
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "cite",
                       let host = url.host(),
                       let index = Int(host),
                       index > 0, index <= sources.count {
                        onSourceTap(sources[index - 1].url)
                        return .handled
                    }
                    onSourceTap(url)
                    return .handled
                })
        }
    }

    private var processedContent: String {
        section.content
    }
}

// MARK: - Custom Markdown Theme

@MainActor
extension MarkdownUI.Theme {
    static let browseEditorial = Theme()
        .text {
            FontSize(16)
            ForegroundColor(.primary)
        }
        .link {
            ForegroundColor(BrowseColor.accent)
        }
        .strong {
            FontWeight(.semibold)
        }
        .code {
            FontSize(14)
            FontFamilyVariant(.monospaced)
            BackgroundColor(Color.primary.opacity(0.04))
        }
        .paragraph { configuration in
            configuration.label
                .lineSpacing(5)
                .markdownMargin(top: 0, bottom: 12)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 4, bottom: 4)
        }
        .table { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .fixedSize(horizontal: true, vertical: false)
            }
            .markdownTableBorderStyle(
                .init(color: BrowseColor.borderSubtle)
            )
            .markdownTableBackgroundStyle(
                .alternatingRows(
                    Color.clear,
                    BrowseColor.surfaceSubtle.opacity(0.6)
                )
            )
            .markdownMargin(top: 6, bottom: 16)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                    BackgroundColor(nil)
                }
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .relativeLineSpacing(.em(0.2))
        }
}
