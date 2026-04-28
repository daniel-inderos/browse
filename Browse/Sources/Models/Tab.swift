import Foundation
import SwiftUI

enum TabKind: String, Codable, Equatable {
    case web
    case briefing
}

@Observable
final class Tab: Identifiable {
    let id: UUID
    var kind: TabKind
    var title: String
    var url: URL?
    var groupID: UUID?
    var faviconURL: URL?
    var tintColor: Color?
    var pageZoom: Double?
    var isLoading: Bool
    var isFavorite: Bool
    var isPinned: Bool
    var createdAt: Date
    var lastAccessedAt: Date

    var briefingViewModel: BriefingViewModel?
    var webTabViewModel: WebTabViewModel?

    // MARK: - Staleness / Decay

    /// Hours since last interaction
    var hoursSinceLastAccess: Double {
        Date().timeIntervalSince(lastAccessedAt) / 3600
    }

    /// True when the tab has had no interaction for ~4 hours
    var isStale: Bool {
        hoursSinceLastAccess >= 4
    }

    /// Opacity multiplier: 1.0 for fresh tabs, ramps down to ~0.45 for very old tabs.
    /// Favorite and pinned tabs are exempt from decay.
    var decayOpacity: Double {
        guard !isFavorite && !isPinned else { return 1.0 }
        let hours = hoursSinceLastAccess
        if hours < 4 { return 1.0 }
        // Clamp between 0.45 and 1.0, decaying over 4..48 hours
        return max(0.45, 1.0 - (hours - 4) / 88)
    }

    init(
        id: UUID = UUID(),
        kind: TabKind,
        title: String = "New Tab",
        url: URL? = nil,
        groupID: UUID? = nil,
        pageZoom: Double? = nil,
        isFavorite: Bool = false,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.url = url
        self.groupID = groupID
        self.pageZoom = pageZoom
        self.isLoading = false
        self.isFavorite = isFavorite
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }
}
