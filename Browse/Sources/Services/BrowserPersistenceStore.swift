import Foundation
import OSLog

private let persistenceLogger = Logger(subsystem: "com.browse.app", category: "Persistence")

enum PersistedBriefingPhase: Codable {
    case idle
    case searching
    case synthesizing
    case complete
    case error(String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case message
    }

    private enum Kind: String, Codable {
        case idle
        case searching
        case synthesizing
        case complete
        case error
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .idle:
            self = .idle
        case .searching:
            self = .searching
        case .synthesizing:
            self = .synthesizing
        case .complete:
            self = .complete
        case .error:
            self = .error(try container.decode(String.self, forKey: .message))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try container.encode(Kind.idle, forKey: .kind)
        case .searching:
            try container.encode(Kind.searching, forKey: .kind)
        case .synthesizing:
            try container.encode(Kind.synthesizing, forKey: .kind)
        case .complete:
            try container.encode(Kind.complete, forKey: .kind)
        case .error(let message):
            try container.encode(Kind.error, forKey: .kind)
            try container.encode(message, forKey: .message)
        }
    }
}

struct PersistedBriefingSnapshot: Codable {
    let document: BriefingDocument
    let phase: PersistedBriefingPhase
    let conversationHistory: [ConversationMessage]
}

struct PersistedTabSnapshot: Codable {
    let id: UUID
    let kind: TabKind
    let title: String
    let url: URL?
    var groupID: UUID? = nil
    let navigationHistory: [URL]?
    let navigationHistoryIndex: Int?
    let isFavorite: Bool?
    let isPinned: Bool
    let createdAt: Date
    let lastAccessedAt: Date
    let briefing: PersistedBriefingSnapshot?
}

struct PersistedTabGroupSnapshot: Codable {
    let id: UUID
    let title: String
    let isCollapsed: Bool
    let createdAt: Date
}

struct PersistedPageChatSnapshot: Codable {
    let pageURL: URL
    let pageTitle: String
    let conversationHistory: [ConversationMessage]
    let updatedAt: Date
    let isSidebarVisible: Bool?
}

struct PersistedBrowserState: Codable {
    let tabs: [PersistedTabSnapshot]
    var tabGroups: [PersistedTabGroupSnapshot]? = nil
    let activeTabID: UUID?
    let isTabBarVisible: Bool
    let tabBarWidth: Double
    let chatPaneWidth: Double?
    let chatPaneHeight: Double?
    let chatPaneOffsetX: Double?
    let chatPaneOffsetY: Double?
    let pageChats: [PersistedPageChatSnapshot]?
}

struct PersistedBrowserWindowSnapshot: Codable {
    let id: UUID
    let state: PersistedBrowserState
    let lastUpdatedAt: Date
}

struct PersistedBrowserWindowSession: Codable {
    let windows: [PersistedBrowserWindowSnapshot]
}

struct BrowserPersistenceStore {
    private let fileManager = FileManager.default
    private let fileURL: URL
    private let sessionFileURL: URL

    init(
        filename: String = "browser-state.json",
        sessionFilename: String = "browser-session.json",
        directoryURL: URL? = nil
    ) {
        let directory: URL
        if let directoryURL {
            directory = directoryURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            directory = appSupport.appendingPathComponent("Browse", isDirectory: true)
        }

        self.fileURL = directory.appendingPathComponent(filename, isDirectory: false)
        self.sessionFileURL = directory.appendingPathComponent(sessionFilename, isDirectory: false)
    }

    func loadRestorableWindowIDs() -> [UUID] {
        loadSession()?.windows
            .filter { $0.state.isRestorableWindowState }
            .sorted { $0.lastUpdatedAt < $1.lastUpdatedAt }
            .map(\.id) ?? []
    }

    func loadWindowState(
        forWindowID windowID: UUID,
        allowsLegacyFallback: Bool = true
    ) -> PersistedBrowserState? {
        if let session = loadSession() {
            return session.windows.first { $0.id == windowID }?.state
        }

        return allowsLegacyFallback ? load() : nil
    }

    func save(_ state: PersistedBrowserState, forWindowID windowID: UUID) {
        do {
            guard state.isRestorableWindowState else {
                removeWindowState(forWindowID: windowID)
                return
            }

            var snapshots = loadSession()?.windows ?? []
            let snapshot = PersistedBrowserWindowSnapshot(
                id: windowID,
                state: state,
                lastUpdatedAt: Date()
            )

            if let index = snapshots.firstIndex(where: { $0.id == windowID }) {
                snapshots[index] = snapshot
            } else {
                snapshots.append(snapshot)
            }

            try saveSession(PersistedBrowserWindowSession(windows: snapshots))
        } catch {
            persistenceLogger.error("Failed to save window state; category=\(Self.errorCategory(error), privacy: .public)")
        }
    }

    func removeWindowState(forWindowID windowID: UUID) {
        do {
            guard var snapshots = loadSession()?.windows else { return }
            snapshots.removeAll { $0.id == windowID }
            try saveSession(PersistedBrowserWindowSession(windows: snapshots))
        } catch {
            persistenceLogger.error("Failed to remove window state; category=\(Self.errorCategory(error), privacy: .public)")
        }
    }

    func pruneWindowStates(keepingWindowIDs windowIDs: Set<UUID>) {
        do {
            let snapshots = loadSession()?.windows ?? []
            let prunedSnapshots = snapshots.filter { snapshot in
                windowIDs.contains(snapshot.id) && snapshot.state.isRestorableWindowState
            }
            try saveSession(PersistedBrowserWindowSession(windows: prunedSnapshots))
        } catch {
            persistenceLogger.error("Failed to prune window states; category=\(Self.errorCategory(error), privacy: .public)")
        }
    }

    func load() -> PersistedBrowserState? {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(PersistedBrowserState.self, from: data)
        } catch {
            return nil
        }
    }

    func save(_ state: PersistedBrowserState) {
        do {
            try write(state, to: fileURL)
        } catch {
            // Persistence errors should never crash the app.
            persistenceLogger.error("Failed to save state; category=\(Self.errorCategory(error), privacy: .public)")
        }
    }

    func clearBrowsingData() throws {
        try removeFileIfPresent(fileURL)
        try removeFileIfPresent(sessionFileURL)
    }

    func clearAIHistory() throws {
        if let session = loadSession() {
            try saveSession(session.clearingAIHistory())
        }
        if let state = load() {
            try write(state.clearingAIHistory(), to: fileURL)
        }
    }

    func applyRetention(_ settings: DataRetentionSettingsManager = .shared, now: Date = Date()) throws {
        if let cutoff = settings.browsingDataRetention.cutoffDate(relativeTo: now) {
            try pruneBrowsingData(olderThan: cutoff)
        }
        if let cutoff = settings.aiHistoryRetention.cutoffDate(relativeTo: now) {
            try pruneAIHistory(olderThan: cutoff)
        }
    }

    func pruneBrowsingData(olderThan cutoff: Date) throws {
        if let session = loadSession() {
            let windows = session.windows.compactMap { snapshot -> PersistedBrowserWindowSnapshot? in
                let state = snapshot.state.pruningBrowsingData(olderThan: cutoff)
                guard state.isRestorableWindowState else { return nil }
                return PersistedBrowserWindowSnapshot(
                    id: snapshot.id,
                    state: state,
                    lastUpdatedAt: snapshot.lastUpdatedAt
                )
            }
            try saveSession(PersistedBrowserWindowSession(windows: windows))
        }

        if let state = load() {
            try write(state.pruningBrowsingData(olderThan: cutoff), to: fileURL)
        }
    }

    func pruneAIHistory(olderThan cutoff: Date) throws {
        if let session = loadSession() {
            let windows = session.windows.map { snapshot in
                PersistedBrowserWindowSnapshot(
                    id: snapshot.id,
                    state: snapshot.state.pruningAIHistory(olderThan: cutoff),
                    lastUpdatedAt: snapshot.lastUpdatedAt
                )
            }
            try saveSession(PersistedBrowserWindowSession(windows: windows))
        }

        if let state = load() {
            try write(state.pruningAIHistory(olderThan: cutoff), to: fileURL)
        }
    }

    private func loadSession() -> PersistedBrowserWindowSession? {
        do {
            let data = try Data(contentsOf: sessionFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(PersistedBrowserWindowSession.self, from: data)
        } catch {
            return nil
        }
    }

    private func saveSession(_ session: PersistedBrowserWindowSession) throws {
        try write(session, to: sessionFileURL)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try ensureDirectoryExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func removeFileIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func ensureDirectoryExists() throws {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private static func errorCategory(_ error: Error) -> String {
        if let cocoaError = error as? CocoaError {
            return "cocoa-\(cocoaError.errorCode)"
        }
        if let posixError = error as? POSIXError {
            return "posix-\(posixError.code.rawValue)"
        }
        return "unknown"
    }
}

private extension PersistedBrowserState {
    var isRestorableWindowState: Bool {
        tabs.contains { snapshot in
            switch snapshot.kind {
            case .briefing:
                return true
            case .web:
                return snapshot.url != nil || snapshot.navigationHistory?.isEmpty == false
            }
        }
    }

    func clearingAIHistory() -> PersistedBrowserState {
        PersistedBrowserState(
            tabs: tabs.map { $0.clearingAIHistory() },
            tabGroups: tabGroups,
            activeTabID: activeTabID,
            isTabBarVisible: isTabBarVisible,
            tabBarWidth: tabBarWidth,
            chatPaneWidth: chatPaneWidth,
            chatPaneHeight: chatPaneHeight,
            chatPaneOffsetX: chatPaneOffsetX,
            chatPaneOffsetY: chatPaneOffsetY,
            pageChats: nil
        )
    }

    func pruningBrowsingData(olderThan cutoff: Date) -> PersistedBrowserState {
        let retainedTabs = tabs.filter { tab in
            tab.kind == .briefing || tab.lastAccessedAt >= cutoff || tab.isPinned || (tab.isFavorite ?? false)
        }
        let retainedActiveTabID = activeTabID.flatMap { id in
            retainedTabs.contains { $0.id == id } ? id : nil
        }

        return PersistedBrowserState(
            tabs: retainedTabs,
            tabGroups: tabGroups,
            activeTabID: retainedActiveTabID ?? retainedTabs.first?.id,
            isTabBarVisible: isTabBarVisible,
            tabBarWidth: tabBarWidth,
            chatPaneWidth: chatPaneWidth,
            chatPaneHeight: chatPaneHeight,
            chatPaneOffsetX: chatPaneOffsetX,
            chatPaneOffsetY: chatPaneOffsetY,
            pageChats: pageChats
        )
    }

    func pruningAIHistory(olderThan cutoff: Date) -> PersistedBrowserState {
        PersistedBrowserState(
            tabs: tabs.map { $0.pruningAIHistory(olderThan: cutoff) },
            tabGroups: tabGroups,
            activeTabID: activeTabID,
            isTabBarVisible: isTabBarVisible,
            tabBarWidth: tabBarWidth,
            chatPaneWidth: chatPaneWidth,
            chatPaneHeight: chatPaneHeight,
            chatPaneOffsetX: chatPaneOffsetX,
            chatPaneOffsetY: chatPaneOffsetY,
            pageChats: pageChats?.filter { $0.updatedAt >= cutoff }
        )
    }
}

private extension PersistedTabSnapshot {
    func clearingAIHistory() -> PersistedTabSnapshot {
        PersistedTabSnapshot(
            id: id,
            kind: kind,
            title: title,
            url: url,
            groupID: groupID,
            navigationHistory: navigationHistory,
            navigationHistoryIndex: navigationHistoryIndex,
            isFavorite: isFavorite,
            isPinned: isPinned,
            createdAt: createdAt,
            lastAccessedAt: lastAccessedAt,
            briefing: briefing?.clearingAIHistory()
        )
    }

    func pruningAIHistory(olderThan cutoff: Date) -> PersistedTabSnapshot {
        guard lastAccessedAt < cutoff else { return self }
        return clearingAIHistory()
    }
}

private extension PersistedBriefingSnapshot {
    func clearingAIHistory() -> PersistedBriefingSnapshot {
        PersistedBriefingSnapshot(
            document: document,
            phase: phase,
            conversationHistory: []
        )
    }
}

private extension PersistedBrowserWindowSession {
    func clearingAIHistory() -> PersistedBrowserWindowSession {
        PersistedBrowserWindowSession(
            windows: windows.map { snapshot in
                PersistedBrowserWindowSnapshot(
                    id: snapshot.id,
                    state: snapshot.state.clearingAIHistory(),
                    lastUpdatedAt: snapshot.lastUpdatedAt
                )
            }
        )
    }
}
