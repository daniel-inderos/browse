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
    let navigationHistory: [URL]?
    let navigationHistoryIndex: Int?
    let isFavorite: Bool?
    let isPinned: Bool
    let createdAt: Date
    let lastAccessedAt: Date
    let briefing: PersistedBriefingSnapshot?
}

struct PersistedPageChatSnapshot: Codable {
    let pageURL: URL
    let pageTitle: String
    let conversationHistory: [ConversationMessage]
    let updatedAt: Date
}

struct PersistedBrowserState: Codable {
    let tabs: [PersistedTabSnapshot]
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
            try ensureDirectoryExists()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persistence errors should never crash the app.
            persistenceLogger.error("Failed to save state; category=\(Self.errorCategory(error), privacy: .public)")
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
        try ensureDirectoryExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        try data.write(to: sessionFileURL, options: .atomic)
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
}
