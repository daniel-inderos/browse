import Foundation

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

struct BrowserPersistenceStore {
    private let fileManager = FileManager.default
    private let fileURL: URL

    init(filename: String = "browser-state.json") {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = appSupport.appendingPathComponent("Browse", isDirectory: true)
        self.fileURL = directory.appendingPathComponent(filename, isDirectory: false)
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
            print("[Browse/Persistence] Failed to save state: \(error)")
        }
    }

    private func ensureDirectoryExists() throws {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
