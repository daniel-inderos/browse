import SwiftUI

struct BriefingHeaderView: View {
    let query: String
    let headline: String
    let tldr: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Query context — small, understated label
            HStack(spacing: 6) {
                Circle()
                    .fill(BrowseColor.briefBadge)
                    .frame(width: 6, height: 6)

                Text(query)
                    .font(BrowseFont.briefingCaption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            // Headline — commanding, editorial
            if !headline.isEmpty {
                Text(headline)
                    .font(BrowseFont.briefingHeadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }

            // TL;DR — left-bordered pull quote style
            if !tldr.isEmpty {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(BrowseColor.accent.opacity(0.5))
                        .frame(width: 3)

                    Text(tldr)
                        .font(BrowseFont.briefingTLDR)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(4)
                        .padding(.leading, 16)
                        .padding(.vertical, 4)
                }
                .padding(.top, 4)
            }
        }
    }
}
