import Foundation
import Observation

enum DataRetentionPeriod: String, CaseIterable, Identifiable, Codable {
    case forever
    case oneDay
    case sevenDays
    case thirtyDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forever:
            return "Until I clear it"
        case .oneDay:
            return "1 day"
        case .sevenDays:
            return "7 days"
        case .thirtyDays:
            return "30 days"
        }
    }

    func cutoffDate(relativeTo now: Date = Date()) -> Date? {
        let days: Int
        switch self {
        case .forever:
            return nil
        case .oneDay:
            days = 1
        case .sevenDays:
            days = 7
        case .thirtyDays:
            days = 30
        }

        return Calendar.current.date(byAdding: .day, value: -days, to: now)
    }
}

@Observable
final class DataRetentionSettingsManager: @unchecked Sendable {
    static let shared = DataRetentionSettingsManager()

    static let browsingDataRetentionKey = "retention.browsingData"
    static let aiHistoryRetentionKey = "retention.aiHistory"

    var browsingDataRetention: DataRetentionPeriod {
        didSet {
            guard browsingDataRetention != oldValue else { return }
            UserDefaults.standard.set(browsingDataRetention.rawValue, forKey: Self.browsingDataRetentionKey)
            NotificationCenter.default.post(name: .browseDataRetentionSettingsChanged, object: nil)
        }
    }

    var aiHistoryRetention: DataRetentionPeriod {
        didSet {
            guard aiHistoryRetention != oldValue else { return }
            UserDefaults.standard.set(aiHistoryRetention.rawValue, forKey: Self.aiHistoryRetentionKey)
            NotificationCenter.default.post(name: .browseDataRetentionSettingsChanged, object: nil)
        }
    }

    private init() {
        self.browsingDataRetention = Self.loadPeriod(forKey: Self.browsingDataRetentionKey)
        self.aiHistoryRetention = Self.loadPeriod(forKey: Self.aiHistoryRetentionKey)
    }

    private static func loadPeriod(forKey key: String) -> DataRetentionPeriod {
        guard let rawValue = UserDefaults.standard.string(forKey: key),
              let period = DataRetentionPeriod(rawValue: rawValue) else {
            return .forever
        }
        return period
    }
}

extension Notification.Name {
    static let browseClearBrowsingDataRequested = Notification.Name("browse.clearBrowsingDataRequested")
    static let browseClearAIHistoryRequested = Notification.Name("browse.clearAIHistoryRequested")
    static let browseDataRetentionSettingsChanged = Notification.Name("browse.dataRetentionSettingsChanged")
}
