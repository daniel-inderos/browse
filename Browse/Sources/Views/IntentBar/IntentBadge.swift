import SwiftUI

struct IntentBadge: View {
    let classification: IntentClassification?

    var body: some View {
        if let classification {
            HStack(spacing: 4) {
                Image(systemName: badgeIcon)
                    .font(.system(size: 8, weight: .bold))
                Text(classification.label.uppercased())
                    .font(BrowseFont.badge)
                    .tracking(0.5)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor, in: Capsule())
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }

    private var badgeIcon: String {
        guard let classification else { return "questionmark" }
        switch classification {
        case .open: return "arrow.up.right"
        case .brief: return "sparkles"
        case .search: return "magnifyingglass"
        }
    }

    private var badgeColor: Color {
        guard let classification else { return .gray }
        switch classification {
        case .open: return BrowseColor.openBadge
        case .brief: return BrowseColor.briefBadge
        case .search: return BrowseColor.searchBadge
        }
    }
}
