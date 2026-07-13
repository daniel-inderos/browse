import Foundation
import OSLog
import SQLite3

private let persistenceLogger = Logger(subsystem: "com.browse.app", category: "Persistence")
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

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
    var pageZoom: Double? = nil
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

struct PersistedWorkspace: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
    var colorName: String?
    var iconName: String?
    var isDefault: Bool
}

struct BrowserPersistenceStore {
    private static let legacyJSONMigrationKey = "legacy-json-migrated"
    private static let lastOpenedWorkspaceIDKey = "last-opened-workspace-id"
    private static let globalFavoritesKey = "global-favorites"
    private static let globalFavoritesMigrationKey = "global-favorites-migrated"
    private static let legacyStateWindowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let defaultWorkspaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

    private let fileManager = FileManager.default
    private let fileURL: URL
    private let sessionFileURL: URL
    private let databaseURL: URL

    init(
        filename: String = "browser-state.json",
        sessionFilename: String = "browser-session.json",
        databaseFilename: String = "browser.sqlite",
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
        self.databaseURL = directory.appendingPathComponent(databaseFilename, isDirectory: false)
    }

    func loadRestorableWindowIDs() -> [UUID] {
        do {
            return try withDatabase { database in
                try loadWindowIDs(in: database)
            }
        } catch {
            persistenceLogger.error("Failed to load window ids; category=\(Self.errorCategory(error), privacy: .public)")
            return []
        }
    }

    func loadWindowState(
        forWindowID windowID: UUID,
        allowsLegacyFallback: Bool = true
    ) -> PersistedBrowserState? {
        do {
            return try withDatabase(legacyStateWindowID: windowID) { database in
                try loadWindowState(forWindowID: windowID, in: database)
            }
        } catch {
            persistenceLogger.error("Failed to load window state; category=\(Self.errorCategory(error), privacy: .public)")
            return allowsLegacyFallback ? loadLegacyState() : nil
        }
    }

    func workspaceID(forWindowID windowID: UUID) -> UUID? {
        do {
            return try withDatabase { database in
                try loadWorkspaceID(forWindowID: windowID, in: database)
            }
        } catch {
            persistenceLogger.error("Failed to load window workspace id; category=\(Self.errorCategory(error), privacy: .public)")
            return nil
        }
    }

    func loadWorkspaces() -> [PersistedWorkspace] {
        do {
            return try withDatabase { database in
                try ensureDefaultWorkspace(in: database)
                return try loadWorkspaceRows(in: database)
            }
        } catch {
            persistenceLogger.error("Failed to load workspaces; category=\(Self.errorCategory(error), privacy: .public)")
            return [Self.defaultWorkspace()]
        }
    }

    func loadWorkspaceState(forWorkspaceID workspaceID: UUID) -> PersistedBrowserState? {
        do {
            return try withDatabase { database in
                try loadWorkspaceState(forWorkspaceID: workspaceID, in: database)
            }
        } catch {
            persistenceLogger.error("Failed to load workspace state; category=\(Self.errorCategory(error), privacy: .public)")
            return nil
        }
    }

    func loadLastOpenedWorkspaceID() -> UUID? {
        do {
            return try withDatabase { database in
                try metadataValue(forKey: Self.lastOpenedWorkspaceIDKey, in: database)
                    .flatMap(UUID.init(uuidString:))
            }
        } catch {
            persistenceLogger.error("Failed to load last workspace id; category=\(Self.errorCategory(error), privacy: .public)")
            return nil
        }
    }

    @discardableResult
    func createWorkspace(
        name: String,
        colorName: String? = nil,
        iconName: String? = nil,
        state: PersistedBrowserState? = nil
    ) -> PersistedWorkspace {
        do {
            return try withDatabase { database in
                let now = Date()
                let workspace = PersistedWorkspace(
                    id: UUID(),
                    name: Self.normalizedWorkspaceName(name, fallback: "New Workspace"),
                    createdAt: now,
                    updatedAt: now,
                    lastOpenedAt: now,
                    colorName: colorName,
                    iconName: iconName,
                    isDefault: false
                )
                try database.transaction {
                    try insertWorkspace(workspace, in: database)
                    if let state {
                        try saveWorkspaceState(
                            state,
                            forWorkspaceID: workspace.id,
                            updatedAt: now,
                            in: database,
                            beginsTransaction: false
                        )
                    }
                }
                return workspace
            }
        } catch {
            persistenceLogger.error("Failed to create workspace; category=\(Self.errorCategory(error), privacy: .public)")
            return Self.defaultWorkspace()
        }
    }

    func renameWorkspace(_ workspaceID: UUID, name: String) {
        do {
            try withDatabase { database in
                try database.prepare(
                    "UPDATE workspaces SET name = ?, updated_at = ? WHERE id = ?"
                ) { statement in
                    try bindText(Self.normalizedWorkspaceName(name, fallback: "Workspace"), to: statement, at: 1, database: database)
                    try bindDate(Date(), to: statement, at: 2, database: database)
                    try bindText(workspaceID.uuidString, to: statement, at: 3, database: database)
                    try stepDone(statement, database: database)
                }
            }
        } catch {
            persistenceLogger.error("Failed to rename workspace; category=\(Self.errorCategory(error), privacy: .public)")
        }
    }

    func markWorkspaceOpened(_ workspaceID: UUID, forWindowID windowID: UUID) {
        do {
            try withDatabase { database in
                try database.transaction {
                    try ensureDefaultWorkspace(in: database)
                    try database.prepare(
                        "UPDATE workspaces SET last_opened_at = ?, updated_at = ? WHERE id = ?"
                    ) { statement in
                        let now = Date()
                        try bindDate(now, to: statement, at: 1, database: database)
                        try bindDate(now, to: statement, at: 2, database: database)
                        try bindText(workspaceID.uuidString, to: statement, at: 3, database: database)
                        try stepDone(statement, database: database)
                    }
                    try setWindowWorkspaceID(workspaceID, forWindowID: windowID, in: database)
                    try setMetadataValue(workspaceID.uuidString, forKey: Self.lastOpenedWorkspaceIDKey, in: database)
                }
            }
        } catch {
            persistenceLogger.error("Failed to mark workspace opened; category=\(Self.errorCategory(error), privacy: .public)")
        }
    }

    func deleteWorkspace(_ workspaceID: UUID) {
        guard workspaceID != Self.defaultWorkspaceID else { return }
        do {
            try withDatabase { database in
                try database.transaction {
                    try database.prepare("DELETE FROM workspace_states WHERE workspace_id = ?") { statement in
                        try bindText(workspaceID.uuidString, to: statement, at: 1, database: database)
                        try stepDone(statement, database: database)
                    }
                    try database.prepare("DELETE FROM workspaces WHERE id = ? AND is_default = 0") { statement in
                        try bindText(workspaceID.uuidString, to: statement, at: 1, database: database)
                        try stepDone(statement, database: database)
                    }
                    try database.prepare("UPDATE windows SET workspace_id = ? WHERE workspace_id = ?") { statement in
                        try bindText(Self.defaultWorkspaceID.uuidString, to: statement, at: 1, database: database)
                        try bindText(workspaceID.uuidString, to: statement, at: 2, database: database)
                        try stepDone(statement, database: database)
                    }
                    try database.prepare(
                        "UPDATE window_workspace_selection SET workspace_id = ?, updated_at = ? WHERE workspace_id = ?"
                    ) { statement in
                        try bindText(Self.defaultWorkspaceID.uuidString, to: statement, at: 1, database: database)
                        try bindDate(Date(), to: statement, at: 2, database: database)
                        try bindText(workspaceID.uuidString, to: statement, at: 3, database: database)
                        try stepDone(statement, database: database)
                    }
                }
            }
        } catch {
            persistenceLogger.error("Failed to delete workspace; category=\(Self.errorCategory(error), privacy: .public)")
        }
    }

    @discardableResult
    func duplicateWorkspace(_ workspaceID: UUID, name: String? = nil) -> PersistedWorkspace? {
        do {
            return try withDatabase { database in
                guard let source = try loadWorkspaceRows(in: database).first(where: { $0.id == workspaceID }) else {
                    return nil
                }
                let state = try loadWorkspaceState(forWorkspaceID: workspaceID, in: database)
                let now = Date()
                let duplicate = PersistedWorkspace(
                    id: UUID(),
                    name: Self.normalizedWorkspaceName(name ?? "\(source.name) Copy", fallback: "Workspace Copy"),
                    createdAt: now,
                    updatedAt: now,
                    lastOpenedAt: nil,
                    colorName: source.colorName,
                    iconName: source.iconName,
                    isDefault: false
                )
                try database.transaction {
                    try insertWorkspace(duplicate, in: database)
                    if let state {
                        try saveWorkspaceState(
                            state,
                            forWorkspaceID: duplicate.id,
                            updatedAt: now,
                            in: database,
                            beginsTransaction: false
                        )
                    }
                }
                return duplicate
            }
        } catch {
            persistenceLogger.error("Failed to duplicate workspace; category=\(Self.errorCategory(error), privacy: .public)")
            return nil
        }
    }

    func save(_ state: PersistedBrowserState, forWindowID windowID: UUID) {
        save(state, forWindowID: windowID, workspaceID: Self.defaultWorkspaceID)
    }

    func save(_ state: PersistedBrowserState, forWindowID windowID: UUID, workspaceID: UUID) {
        do {
            try withDatabase { database in
                guard state.isRestorableWindowState else {
                    // A blank window is not evidence that its workspace is
                    // empty (a fresh Cmd-N window shares the last-opened
                    // workspace), so only the window row is removed here.
                    // Workspace snapshots are cleared explicitly via
                    // clearWorkspaceState by the window that owns the content.
                    try deleteWindowState(forWindowID: windowID, in: database)
                    return
                }
                let now = Date()
                try database.transaction {
                    try ensureWorkspaceExists(workspaceID, in: database)
                    try saveWindowState(
                        state,
                        forWindowID: windowID,
                        workspaceID: workspaceID,
                        lastUpdatedAt: now,
                        in: database,
                        beginsTransaction: false
                    )
                    try saveWorkspaceState(
                        state,
                        forWorkspaceID: workspaceID,
                        updatedAt: now,
                        in: database,
                        beginsTransaction: false
                    )
                }
            }
        } catch {
            persistenceLogger.error("Failed to save window state; category=\(Self.errorCategory(error), privacy: .public)")
        }
    }

    func clearWorkspaceState(forWorkspaceID workspaceID: UUID) {
        do {
            try withDatabase { database in
                try deleteWorkspaceState(forWorkspaceID: workspaceID, in: database)
            }
        } catch {
            persistenceLogger.error("Failed to clear workspace state; category=\(Self.errorCategory(error), privacy: .public)")
        }
    }

    func removeWindowState(forWindowID windowID: UUID) {
        do {
            try withDatabase { database in
                try deleteWindowState(forWindowID: windowID, in: database)
            }
        } catch {
            persistenceLogger.error("Failed to remove window state; category=\(Self.errorCategory(error), privacy: .public)")
        }
    }

    func pruneWindowStates(keepingWindowIDs windowIDs: Set<UUID>) {
        do {
            try withDatabase { database in
                try database.transaction {
                    if windowIDs.isEmpty {
                        try database.execute("DELETE FROM windows")
                    } else {
                        let placeholders = Array(repeating: "?", count: windowIDs.count).joined(separator: ", ")
                        try database.prepare("DELETE FROM windows WHERE id NOT IN (\(placeholders))") { statement in
                            for (index, windowID) in windowIDs.enumerated() {
                                try bindText(windowID.uuidString, to: statement, at: Int32(index + 1), database: database)
                            }
                            try stepDone(statement, database: database)
                        }
                    }
                }
            }
        } catch {
            persistenceLogger.error("Failed to prune window states; category=\(Self.errorCategory(error), privacy: .public)")
        }
    }

    func load() -> PersistedBrowserState? {
        do {
            return try withDatabase { database in
                if let state = try loadWindowState(forWindowID: Self.legacyStateWindowID, in: database) {
                    return state
                }
                guard let firstID = try loadWindowIDs(in: database).first else { return nil }
                return try loadWindowState(forWindowID: firstID, in: database)
            }
        } catch {
            persistenceLogger.error("Failed to load state; category=\(Self.errorCategory(error), privacy: .public)")
            return loadLegacyState()
        }
    }

    func save(_ state: PersistedBrowserState) {
        save(state, forWindowID: Self.legacyStateWindowID)
    }

    // MARK: - Global Favorites

    /// Favorites are shared across all workspaces (Arc-style), so they are
    /// stored once, globally, instead of inside each workspace snapshot.
    func loadGlobalFavorites() -> [PersistedTabSnapshot] {
        do {
            return try withDatabase { database in
                try loadGlobalFavorites(in: database)
            }
        } catch {
            persistenceLogger.error("Failed to load global favorites; category=\(Self.errorCategory(error), privacy: .public)")
            return []
        }
    }

    func saveGlobalFavorites(_ favorites: [PersistedTabSnapshot]) {
        do {
            try withDatabase { database in
                try setMetadataValue(
                    try encodeJSON(favorites),
                    forKey: Self.globalFavoritesKey,
                    in: database
                )
            }
        } catch {
            persistenceLogger.error("Failed to save global favorites; category=\(Self.errorCategory(error), privacy: .public)")
        }
    }

    private func loadGlobalFavorites(in database: SQLiteDatabase) throws -> [PersistedTabSnapshot] {
        guard let json = try metadataValue(forKey: Self.globalFavoritesKey, in: database) else {
            return []
        }
        return try decodeJSON([PersistedTabSnapshot].self, from: json)
    }

    /// One-time migration: favorites used to live inside each window and
    /// workspace snapshot. Merge them into the shared global set
    /// (deduplicated by URL) and strip them from the per-workspace snapshots.
    private func migrateGlobalFavoritesIfNeeded(in database: SQLiteDatabase) throws {
        guard try metadataValue(forKey: Self.globalFavoritesMigrationKey, in: database) != "1" else { return }

        var favorites = try loadGlobalFavorites(in: database)
        var seenKeys = Set(favorites.map(\.favoriteDedupeKey))
        func adopt(_ candidates: [PersistedTabSnapshot]) {
            for candidate in candidates where !seenKeys.contains(candidate.favoriteDedupeKey) {
                seenKeys.insert(candidate.favoriteDedupeKey)
                favorites.append(candidate)
            }
        }

        let windowSnapshots = try loadWindowSnapshots(in: database)
        let workspaceStates = try loadWorkspaceStateSnapshots(in: database)

        try database.transaction {
            for snapshot in windowSnapshots {
                let (state, extracted) = snapshot.state.removingFavoriteTabs()
                guard !extracted.isEmpty else { continue }
                adopt(extracted)
                if state.isRestorableWindowState {
                    try saveWindowState(
                        state,
                        forWindowID: snapshot.id,
                        lastUpdatedAt: snapshot.lastUpdatedAt,
                        in: database,
                        beginsTransaction: false
                    )
                } else {
                    try deleteWindowState(forWindowID: snapshot.id, in: database)
                }
            }
            for workspaceState in workspaceStates {
                let (state, extracted) = workspaceState.state.removingFavoriteTabs()
                guard !extracted.isEmpty else { continue }
                adopt(extracted)
                if state.isRestorableWindowState {
                    try saveWorkspaceState(
                        state,
                        forWorkspaceID: workspaceState.workspaceID,
                        updatedAt: workspaceState.updatedAt,
                        in: database,
                        beginsTransaction: false
                    )
                } else {
                    try deleteWorkspaceState(forWorkspaceID: workspaceState.workspaceID, in: database)
                }
            }
            if !favorites.isEmpty {
                try setMetadataValue(
                    try encodeJSON(favorites),
                    forKey: Self.globalFavoritesKey,
                    in: database
                )
            }
            try setMetadataValue("1", forKey: Self.globalFavoritesMigrationKey, in: database)
        }
    }

    func clearBrowsingData() throws {
        for url in [
            databaseURL,
            databaseSidecarURL(suffix: "-wal"),
            databaseSidecarURL(suffix: "-shm"),
            databaseSidecarURL(suffix: "-journal"),
            fileURL,
            sessionFileURL
        ] {
            try removeFileIfPresent(url)
        }
    }

    func clearAIHistory() throws {
        try withDatabase { database in
            let snapshots = try loadWindowSnapshots(in: database)
            let workspaceStates = try loadWorkspaceStateSnapshots(in: database)
            try database.transaction {
                for snapshot in snapshots {
                    try saveWindowState(
                        snapshot.state.clearingAIHistory(),
                        forWindowID: snapshot.id,
                        lastUpdatedAt: snapshot.lastUpdatedAt,
                        in: database,
                        beginsTransaction: false
                    )
                }
                for workspaceState in workspaceStates {
                    try saveWorkspaceState(
                        workspaceState.state.clearingAIHistory(),
                        forWorkspaceID: workspaceState.workspaceID,
                        updatedAt: workspaceState.updatedAt,
                        in: database,
                        beginsTransaction: false
                    )
                }
            }
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
        try withDatabase { database in
            let snapshots = try loadWindowSnapshots(in: database)
            let workspaceStates = try loadWorkspaceStateSnapshots(in: database)
            try database.transaction {
                for snapshot in snapshots {
                    let state = snapshot.state.pruningBrowsingData(olderThan: cutoff)
                    if state.isRestorableWindowState {
                        try saveWindowState(
                            state,
                            forWindowID: snapshot.id,
                            lastUpdatedAt: snapshot.lastUpdatedAt,
                            in: database,
                            beginsTransaction: false
                        )
                    } else {
                        try deleteWindowState(forWindowID: snapshot.id, in: database)
                    }
                }
                for workspaceState in workspaceStates {
                    let state = workspaceState.state.pruningBrowsingData(olderThan: cutoff)
                    if state.isRestorableWindowState {
                        try saveWorkspaceState(
                            state,
                            forWorkspaceID: workspaceState.workspaceID,
                            updatedAt: workspaceState.updatedAt,
                            in: database,
                            beginsTransaction: false
                        )
                    } else {
                        try deleteWorkspaceState(forWorkspaceID: workspaceState.workspaceID, in: database)
                    }
                }
            }
        }
    }

    func pruneAIHistory(olderThan cutoff: Date) throws {
        try withDatabase { database in
            let snapshots = try loadWindowSnapshots(in: database)
            let workspaceStates = try loadWorkspaceStateSnapshots(in: database)
            try database.transaction {
                for snapshot in snapshots {
                    try saveWindowState(
                        snapshot.state.pruningAIHistory(olderThan: cutoff),
                        forWindowID: snapshot.id,
                        lastUpdatedAt: snapshot.lastUpdatedAt,
                        in: database,
                        beginsTransaction: false
                    )
                }
                for workspaceState in workspaceStates {
                    try saveWorkspaceState(
                        workspaceState.state.pruningAIHistory(olderThan: cutoff),
                        forWorkspaceID: workspaceState.workspaceID,
                        updatedAt: workspaceState.updatedAt,
                        in: database,
                        beginsTransaction: false
                    )
                }
            }
        }
    }

    // MARK: - Database setup

    private func withDatabase<T>(
        legacyStateWindowID: UUID? = nil,
        _ body: (SQLiteDatabase) throws -> T
    ) throws -> T {
        try ensureDirectoryExists()
        let database = try SQLiteDatabase(url: databaseURL)
        try createSchema(in: database)
        try migrateSchema(in: database)
        try migrateLegacyJSONIfNeeded(in: database, legacyStateWindowID: legacyStateWindowID)
        try migrateGlobalFavoritesIfNeeded(in: database)
        return try body(database)
    }

    private func createSchema(in database: SQLiteDatabase) throws {
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS windows (
                id TEXT PRIMARY KEY,
                workspace_id TEXT,
                active_tab_id TEXT,
                is_tab_bar_visible INTEGER NOT NULL,
                tab_bar_width REAL NOT NULL,
                chat_pane_width REAL,
                chat_pane_height REAL,
                chat_pane_offset_x REAL,
                chat_pane_offset_y REAL,
                last_updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS workspaces (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                last_opened_at REAL,
                color_name TEXT,
                icon_name TEXT,
                is_default INTEGER NOT NULL
            );

            CREATE INDEX IF NOT EXISTS workspaces_last_opened_idx
            ON workspaces(last_opened_at DESC, updated_at DESC);

            CREATE TABLE IF NOT EXISTS workspace_states (
                workspace_id TEXT PRIMARY KEY REFERENCES workspaces(id) ON DELETE CASCADE,
                state_json TEXT NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS window_workspace_selection (
                window_id TEXT PRIMARY KEY,
                workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS tab_groups (
                id TEXT PRIMARY KEY,
                window_id TEXT NOT NULL REFERENCES windows(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                is_collapsed INTEGER NOT NULL,
                created_at REAL NOT NULL,
                sort_order INTEGER NOT NULL
            );

            CREATE INDEX IF NOT EXISTS tab_groups_window_order_idx
            ON tab_groups(window_id, sort_order);

            CREATE TABLE IF NOT EXISTS tabs (
                id TEXT PRIMARY KEY,
                window_id TEXT NOT NULL REFERENCES windows(id) ON DELETE CASCADE,
                sort_order INTEGER NOT NULL,
                kind TEXT NOT NULL,
                title TEXT NOT NULL,
                url TEXT,
                group_id TEXT,
                navigation_history_index INTEGER,
                is_favorite INTEGER,
                is_pinned INTEGER NOT NULL,
                created_at REAL NOT NULL,
                last_accessed_at REAL NOT NULL,
                page_zoom REAL,
                briefing_document_json TEXT,
                briefing_phase_json TEXT
            );

            CREATE INDEX IF NOT EXISTS tabs_window_order_idx
            ON tabs(window_id, sort_order);

            CREATE TABLE IF NOT EXISTS navigation_entries (
                tab_id TEXT NOT NULL REFERENCES tabs(id) ON DELETE CASCADE,
                sort_order INTEGER NOT NULL,
                url TEXT NOT NULL,
                PRIMARY KEY(tab_id, sort_order)
            );

            CREATE TABLE IF NOT EXISTS briefing_conversation_messages (
                tab_id TEXT NOT NULL REFERENCES tabs(id) ON DELETE CASCADE,
                sort_order INTEGER NOT NULL,
                id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                timestamp REAL NOT NULL,
                PRIMARY KEY(tab_id, sort_order)
            );

            CREATE TABLE IF NOT EXISTS page_chats (
                id TEXT PRIMARY KEY,
                window_id TEXT NOT NULL REFERENCES windows(id) ON DELETE CASCADE,
                page_url TEXT NOT NULL,
                page_title TEXT NOT NULL,
                updated_at REAL NOT NULL,
                is_sidebar_visible INTEGER,
                UNIQUE(window_id, page_url)
            );

            CREATE INDEX IF NOT EXISTS page_chats_window_updated_idx
            ON page_chats(window_id, updated_at DESC);

            CREATE TABLE IF NOT EXISTS page_chat_messages (
                chat_id TEXT NOT NULL REFERENCES page_chats(id) ON DELETE CASCADE,
                sort_order INTEGER NOT NULL,
                id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                timestamp REAL NOT NULL,
                PRIMARY KEY(chat_id, sort_order)
            );
            """
        )
    }

    private func migrateSchema(in database: SQLiteDatabase) throws {
        if try !table("tabs", hasColumn: "page_zoom", in: database) {
            try database.execute("ALTER TABLE tabs ADD COLUMN page_zoom REAL")
        }
        if try !table("windows", hasColumn: "workspace_id", in: database) {
            try database.execute("ALTER TABLE windows ADD COLUMN workspace_id TEXT")
        }
        try ensureDefaultWorkspace(in: database)
        try database.prepare("UPDATE windows SET workspace_id = ? WHERE workspace_id IS NULL") { statement in
            try bindText(Self.defaultWorkspaceID.uuidString, to: statement, at: 1, database: database)
            try stepDone(statement, database: database)
        }
        try database.execute(
            """
            INSERT OR IGNORE INTO window_workspace_selection (window_id, workspace_id, updated_at)
            SELECT id, workspace_id, last_updated_at FROM windows WHERE workspace_id IS NOT NULL
            """
        )
    }

    private func table(_ tableName: String, hasColumn columnName: String, in database: SQLiteDatabase) throws -> Bool {
        var hasColumn = false
        try database.prepare("PRAGMA table_info(\(tableName))") { statement in
            while try stepRow(statement, database: database) {
                if columnText(statement, at: 1) == columnName {
                    hasColumn = true
                    break
                }
            }
        }
        return hasColumn
    }

    private func migrateLegacyJSONIfNeeded(in database: SQLiteDatabase, legacyStateWindowID: UUID?) throws {
        guard try metadataValue(forKey: Self.legacyJSONMigrationKey, in: database) != "1" else { return }

        let legacySession = loadLegacySession()
        let legacyState = legacySession == nil ? loadLegacyState() : nil

        if let session = legacySession {
            for snapshot in session.windows where snapshot.state.isRestorableWindowState {
                try saveWindowState(
                    snapshot.state,
                    forWindowID: snapshot.id,
                    workspaceID: Self.defaultWorkspaceID,
                    lastUpdatedAt: snapshot.lastUpdatedAt,
                    in: database
                )
                if try loadWorkspaceState(forWorkspaceID: Self.defaultWorkspaceID, in: database) == nil {
                    try saveWorkspaceState(
                        snapshot.state,
                        forWorkspaceID: Self.defaultWorkspaceID,
                        updatedAt: snapshot.lastUpdatedAt,
                        in: database
                    )
                }
            }
        } else if let state = legacyState, state.isRestorableWindowState {
            try saveWindowState(
                state,
                forWindowID: legacyStateWindowID ?? Self.legacyStateWindowID,
                workspaceID: Self.defaultWorkspaceID,
                lastUpdatedAt: Date(),
                in: database
            )
            try saveWorkspaceState(
                state,
                forWorkspaceID: Self.defaultWorkspaceID,
                updatedAt: Date(),
                in: database
            )
        }

        try setMetadataValue("1", forKey: Self.legacyJSONMigrationKey, in: database)

        if legacySession != nil || legacyState != nil {
            try? removeFileIfPresent(sessionFileURL)
            try? removeFileIfPresent(fileURL)
        }
    }

    // MARK: - Loading

    private func loadWindowIDs(in database: SQLiteDatabase) throws -> [UUID] {
        var ids: [UUID] = []
        try database.prepare("SELECT id FROM windows ORDER BY last_updated_at ASC") { statement in
            while try stepRow(statement, database: database) {
                if let idString = columnText(statement, at: 0),
                   let id = UUID(uuidString: idString) {
                    ids.append(id)
                }
            }
        }
        return ids
    }

    private func loadWorkspaceID(forWindowID windowID: UUID, in database: SQLiteDatabase) throws -> UUID? {
        var workspaceID: UUID?
        try database.prepare("SELECT workspace_id FROM window_workspace_selection WHERE window_id = ?") { statement in
            try bindText(windowID.uuidString, to: statement, at: 1, database: database)
            if try stepRow(statement, database: database),
               let idString = columnText(statement, at: 0) {
                workspaceID = UUID(uuidString: idString)
            }
        }
        if workspaceID != nil {
            return workspaceID
        }
        try database.prepare("SELECT workspace_id FROM windows WHERE id = ?") { statement in
            try bindText(windowID.uuidString, to: statement, at: 1, database: database)
            if try stepRow(statement, database: database),
               let idString = columnText(statement, at: 0) {
                workspaceID = UUID(uuidString: idString)
            }
        }
        return workspaceID
    }

    private func loadWorkspaceRows(in database: SQLiteDatabase) throws -> [PersistedWorkspace] {
        var workspaces: [PersistedWorkspace] = []
        try database.prepare(
            """
            SELECT id, name, created_at, updated_at, last_opened_at, color_name, icon_name, is_default
            FROM workspaces
            ORDER BY is_default DESC, COALESCE(last_opened_at, updated_at) DESC, name ASC
            """
        ) { statement in
            while try stepRow(statement, database: database) {
                guard let idString = columnText(statement, at: 0),
                      let id = UUID(uuidString: idString) else {
                    continue
                }
                workspaces.append(
                    PersistedWorkspace(
                        id: id,
                        name: columnText(statement, at: 1) ?? "Workspace",
                        createdAt: columnDate(statement, at: 2),
                        updatedAt: columnDate(statement, at: 3),
                        lastOpenedAt: columnOptionalDate(statement, at: 4),
                        colorName: columnText(statement, at: 5),
                        iconName: columnText(statement, at: 6),
                        isDefault: columnBool(statement, at: 7)
                    )
                )
            }
        }
        return workspaces
    }

    private func loadWorkspaceState(forWorkspaceID workspaceID: UUID, in database: SQLiteDatabase) throws -> PersistedBrowserState? {
        var stateJSON: String?
        try database.prepare("SELECT state_json FROM workspace_states WHERE workspace_id = ?") { statement in
            try bindText(workspaceID.uuidString, to: statement, at: 1, database: database)
            if try stepRow(statement, database: database) {
                stateJSON = columnText(statement, at: 0)
            }
        }
        return try stateJSON.map { try decodeJSON(PersistedBrowserState.self, from: $0) }
    }

    private func loadWorkspaceStateSnapshots(in database: SQLiteDatabase) throws -> [PersistedWorkspaceStateSnapshot] {
        var rows: [(workspaceID: UUID, stateJSON: String, updatedAt: Date)] = []
        try database.prepare(
            "SELECT workspace_id, state_json, updated_at FROM workspace_states"
        ) { statement in
            while try stepRow(statement, database: database) {
                guard let idString = columnText(statement, at: 0),
                      let workspaceID = UUID(uuidString: idString),
                      let stateJSON = columnText(statement, at: 1) else {
                    continue
                }
                rows.append(
                    (
                        workspaceID: workspaceID,
                        stateJSON: stateJSON,
                        updatedAt: columnDate(statement, at: 2)
                    )
                )
            }
        }

        return try rows.map { row in
            PersistedWorkspaceStateSnapshot(
                workspaceID: row.workspaceID,
                state: try decodeJSON(PersistedBrowserState.self, from: row.stateJSON),
                updatedAt: row.updatedAt
            )
        }
    }

    private func loadWindowSnapshots(in database: SQLiteDatabase) throws -> [PersistedBrowserWindowSnapshot] {
        var windows: [(id: UUID, lastUpdatedAt: Date)] = []
        try database.prepare("SELECT id, last_updated_at FROM windows ORDER BY last_updated_at ASC") { statement in
            while try stepRow(statement, database: database) {
                guard let idString = columnText(statement, at: 0),
                      let id = UUID(uuidString: idString) else {
                    continue
                }
                windows.append((id: id, lastUpdatedAt: columnDate(statement, at: 1)))
            }
        }

        return try windows.compactMap { window in
            guard let state = try loadWindowState(forWindowID: window.id, in: database) else { return nil }
            return PersistedBrowserWindowSnapshot(id: window.id, state: state, lastUpdatedAt: window.lastUpdatedAt)
        }
    }

    private func loadWindowState(forWindowID windowID: UUID, in database: SQLiteDatabase) throws -> PersistedBrowserState? {
        var windowRow: WindowRow?
        try database.prepare(
            """
            SELECT active_tab_id, is_tab_bar_visible, tab_bar_width, chat_pane_width,
                   chat_pane_height, chat_pane_offset_x, chat_pane_offset_y
            FROM windows
            WHERE id = ?
            """
        ) { statement in
            try bindText(windowID.uuidString, to: statement, at: 1, database: database)
            if try stepRow(statement, database: database) {
                windowRow = WindowRow(
                    activeTabID: columnText(statement, at: 0).flatMap(UUID.init(uuidString:)),
                    isTabBarVisible: columnBool(statement, at: 1),
                    tabBarWidth: columnDouble(statement, at: 2),
                    chatPaneWidth: columnOptionalDouble(statement, at: 3),
                    chatPaneHeight: columnOptionalDouble(statement, at: 4),
                    chatPaneOffsetX: columnOptionalDouble(statement, at: 5),
                    chatPaneOffsetY: columnOptionalDouble(statement, at: 6)
                )
            }
        }

        guard let windowRow else { return nil }

        let tabs = try loadTabs(forWindowID: windowID, in: database)
        let tabGroups = try loadTabGroups(forWindowID: windowID, in: database)
        let pageChats = try loadPageChats(forWindowID: windowID, in: database)

        return PersistedBrowserState(
            tabs: tabs,
            tabGroups: tabGroups.isEmpty ? nil : tabGroups,
            activeTabID: windowRow.activeTabID,
            isTabBarVisible: windowRow.isTabBarVisible,
            tabBarWidth: windowRow.tabBarWidth,
            chatPaneWidth: windowRow.chatPaneWidth,
            chatPaneHeight: windowRow.chatPaneHeight,
            chatPaneOffsetX: windowRow.chatPaneOffsetX,
            chatPaneOffsetY: windowRow.chatPaneOffsetY,
            pageChats: pageChats.isEmpty ? nil : pageChats
        )
    }

    private func loadTabGroups(forWindowID windowID: UUID, in database: SQLiteDatabase) throws -> [PersistedTabGroupSnapshot] {
        var groups: [PersistedTabGroupSnapshot] = []
        try database.prepare(
            """
            SELECT id, title, is_collapsed, created_at
            FROM tab_groups
            WHERE window_id = ?
            ORDER BY sort_order ASC
            """
        ) { statement in
            try bindText(windowID.uuidString, to: statement, at: 1, database: database)
            while try stepRow(statement, database: database) {
                guard let idString = columnText(statement, at: 0),
                      let id = UUID(uuidString: idString) else {
                    continue
                }
                groups.append(
                    PersistedTabGroupSnapshot(
                        id: id,
                        title: columnText(statement, at: 1) ?? "",
                        isCollapsed: columnBool(statement, at: 2),
                        createdAt: columnDate(statement, at: 3)
                    )
                )
            }
        }
        return groups
    }

    private func loadTabs(forWindowID windowID: UUID, in database: SQLiteDatabase) throws -> [PersistedTabSnapshot] {
        var rows: [TabRow] = []
        try database.prepare(
            """
            SELECT id, kind, title, url, group_id, navigation_history_index, is_favorite,
                   is_pinned, created_at, last_accessed_at, briefing_document_json,
                   briefing_phase_json, page_zoom
            FROM tabs
            WHERE window_id = ?
            ORDER BY sort_order ASC
            """
        ) { statement in
            try bindText(windowID.uuidString, to: statement, at: 1, database: database)
            while try stepRow(statement, database: database) {
                guard let idString = columnText(statement, at: 0),
                      let id = UUID(uuidString: idString),
                      let kindString = columnText(statement, at: 1),
                      let kind = TabKind(rawValue: kindString) else {
                    continue
                }

                rows.append(
                    TabRow(
                        id: id,
                        kind: kind,
                        title: columnText(statement, at: 2) ?? "New Tab",
                        url: columnText(statement, at: 3).flatMap(URL.init(string:)),
                        groupID: columnText(statement, at: 4).flatMap(UUID.init(uuidString:)),
                        navigationHistoryIndex: columnOptionalInt(statement, at: 5),
                        isFavorite: columnOptionalBool(statement, at: 6),
                        isPinned: columnBool(statement, at: 7),
                        createdAt: columnDate(statement, at: 8),
                        lastAccessedAt: columnDate(statement, at: 9),
                        briefingDocumentJSON: columnText(statement, at: 10),
                        briefingPhaseJSON: columnText(statement, at: 11),
                        pageZoom: columnOptionalDouble(statement, at: 12)
                    )
                )
            }
        }

        return try rows.map { row in
            PersistedTabSnapshot(
                id: row.id,
                kind: row.kind,
                title: row.title,
                url: row.url,
                groupID: row.groupID,
                navigationHistory: try loadNavigationHistory(forTabID: row.id, in: database),
                navigationHistoryIndex: row.navigationHistoryIndex,
                pageZoom: row.pageZoom,
                isFavorite: row.isFavorite,
                isPinned: row.isPinned,
                createdAt: row.createdAt,
                lastAccessedAt: row.lastAccessedAt,
                briefing: try loadBriefingSnapshot(for: row, in: database)
            )
        }
    }

    private func loadNavigationHistory(forTabID tabID: UUID, in database: SQLiteDatabase) throws -> [URL]? {
        var urls: [URL] = []
        try database.prepare(
            """
            SELECT url
            FROM navigation_entries
            WHERE tab_id = ?
            ORDER BY sort_order ASC
            """
        ) { statement in
            try bindText(tabID.uuidString, to: statement, at: 1, database: database)
            while try stepRow(statement, database: database) {
                if let urlString = columnText(statement, at: 0),
                   let url = URL(string: urlString) {
                    urls.append(url)
                }
            }
        }
        return urls.isEmpty ? nil : urls
    }

    private func loadBriefingSnapshot(for row: TabRow, in database: SQLiteDatabase) throws -> PersistedBriefingSnapshot? {
        guard let documentJSON = row.briefingDocumentJSON,
              let phaseJSON = row.briefingPhaseJSON else {
            return nil
        }

        return PersistedBriefingSnapshot(
            document: try decodeJSON(BriefingDocument.self, from: documentJSON),
            phase: try decodeJSON(PersistedBriefingPhase.self, from: phaseJSON),
            conversationHistory: try loadConversationMessages(
                from: "briefing_conversation_messages",
                ownerColumn: "tab_id",
                ownerID: row.id.uuidString,
                in: database
            )
        )
    }

    private func loadPageChats(forWindowID windowID: UUID, in database: SQLiteDatabase) throws -> [PersistedPageChatSnapshot] {
        var rows: [PageChatRow] = []
        try database.prepare(
            """
            SELECT id, page_url, page_title, updated_at, is_sidebar_visible
            FROM page_chats
            WHERE window_id = ?
            ORDER BY updated_at DESC
            """
        ) { statement in
            try bindText(windowID.uuidString, to: statement, at: 1, database: database)
            while try stepRow(statement, database: database) {
                guard let id = columnText(statement, at: 0),
                      let pageURLString = columnText(statement, at: 1),
                      let pageURL = URL(string: pageURLString) else {
                    continue
                }
                rows.append(
                    PageChatRow(
                        id: id,
                        pageURL: pageURL,
                        pageTitle: columnText(statement, at: 2) ?? pageURL.displayHost,
                        updatedAt: columnDate(statement, at: 3),
                        isSidebarVisible: columnOptionalBool(statement, at: 4)
                    )
                )
            }
        }

        return try rows.map { row in
            PersistedPageChatSnapshot(
                pageURL: row.pageURL,
                pageTitle: row.pageTitle,
                conversationHistory: try loadConversationMessages(
                    from: "page_chat_messages",
                    ownerColumn: "chat_id",
                    ownerID: row.id,
                    in: database
                ),
                updatedAt: row.updatedAt,
                isSidebarVisible: row.isSidebarVisible
            )
        }
    }

    private func loadConversationMessages(
        from tableName: String,
        ownerColumn: String,
        ownerID: String,
        in database: SQLiteDatabase
    ) throws -> [ConversationMessage] {
        var messages: [ConversationMessage] = []
        try database.prepare(
            """
            SELECT id, role, content, timestamp
            FROM \(tableName)
            WHERE \(ownerColumn) = ?
            ORDER BY sort_order ASC
            """
        ) { statement in
            try bindText(ownerID, to: statement, at: 1, database: database)
            while try stepRow(statement, database: database) {
                guard let idString = columnText(statement, at: 0),
                      let id = UUID(uuidString: idString),
                      let roleString = columnText(statement, at: 1),
                      let role = ConversationMessage.Role(rawValue: roleString),
                      let content = columnText(statement, at: 2) else {
                    continue
                }
                messages.append(
                    ConversationMessage(
                        id: id,
                        role: role,
                        content: content,
                        timestamp: columnDate(statement, at: 3)
                    )
                )
            }
        }
        return messages
    }

    // MARK: - Saving

    private func saveWindowState(
        _ state: PersistedBrowserState,
        forWindowID windowID: UUID,
        workspaceID: UUID = Self.defaultWorkspaceID,
        lastUpdatedAt: Date,
        in database: SQLiteDatabase,
        beginsTransaction: Bool = true
    ) throws {
        let work = {
            try deleteWindowState(forWindowID: windowID, in: database)
            try insertWindowState(
                state,
                forWindowID: windowID,
                workspaceID: workspaceID,
                lastUpdatedAt: lastUpdatedAt,
                in: database
            )
        }

        if beginsTransaction {
            try database.transaction(work)
        } else {
            try work()
        }
    }

    private func insertWindowState(
        _ state: PersistedBrowserState,
        forWindowID windowID: UUID,
        workspaceID: UUID,
        lastUpdatedAt: Date,
        in database: SQLiteDatabase
    ) throws {
        try database.prepare(
            """
            INSERT INTO windows (
                id, workspace_id, active_tab_id, is_tab_bar_visible, tab_bar_width, chat_pane_width,
                chat_pane_height, chat_pane_offset_x, chat_pane_offset_y, last_updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        ) { statement in
            try bindText(windowID.uuidString, to: statement, at: 1, database: database)
            try bindText(workspaceID.uuidString, to: statement, at: 2, database: database)
            try bindText(state.activeTabID?.uuidString, to: statement, at: 3, database: database)
            try bindBool(state.isTabBarVisible, to: statement, at: 4, database: database)
            try bindDouble(state.tabBarWidth, to: statement, at: 5, database: database)
            try bindOptionalDouble(state.chatPaneWidth, to: statement, at: 6, database: database)
            try bindOptionalDouble(state.chatPaneHeight, to: statement, at: 7, database: database)
            try bindOptionalDouble(state.chatPaneOffsetX, to: statement, at: 8, database: database)
            try bindOptionalDouble(state.chatPaneOffsetY, to: statement, at: 9, database: database)
            try bindDate(lastUpdatedAt, to: statement, at: 10, database: database)
            try stepDone(statement, database: database)
        }

        for (index, group) in (state.tabGroups ?? []).enumerated() {
            try insertTabGroup(group, forWindowID: windowID, sortOrder: index, in: database)
        }
        for (index, tab) in state.tabs.enumerated() {
            try insertTab(tab, forWindowID: windowID, sortOrder: index, in: database)
        }
        for pageChat in state.pageChats ?? [] {
            try insertPageChat(pageChat, forWindowID: windowID, in: database)
        }
    }

    private func insertTabGroup(
        _ group: PersistedTabGroupSnapshot,
        forWindowID windowID: UUID,
        sortOrder: Int,
        in database: SQLiteDatabase
    ) throws {
        try database.prepare(
            """
            INSERT INTO tab_groups (id, window_id, title, is_collapsed, created_at, sort_order)
            VALUES (?, ?, ?, ?, ?, ?)
            """
        ) { statement in
            try bindText(group.id.uuidString, to: statement, at: 1, database: database)
            try bindText(windowID.uuidString, to: statement, at: 2, database: database)
            try bindText(group.title, to: statement, at: 3, database: database)
            try bindBool(group.isCollapsed, to: statement, at: 4, database: database)
            try bindDate(group.createdAt, to: statement, at: 5, database: database)
            try bindInt(sortOrder, to: statement, at: 6, database: database)
            try stepDone(statement, database: database)
        }
    }

    private func insertTab(
        _ tab: PersistedTabSnapshot,
        forWindowID windowID: UUID,
        sortOrder: Int,
        in database: SQLiteDatabase
    ) throws {
        try database.prepare(
            """
            INSERT INTO tabs (
                id, window_id, sort_order, kind, title, url, group_id,
                navigation_history_index, is_favorite, is_pinned, created_at,
                last_accessed_at, page_zoom, briefing_document_json, briefing_phase_json
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        ) { statement in
            try bindText(tab.id.uuidString, to: statement, at: 1, database: database)
            try bindText(windowID.uuidString, to: statement, at: 2, database: database)
            try bindInt(sortOrder, to: statement, at: 3, database: database)
            try bindText(tab.kind.rawValue, to: statement, at: 4, database: database)
            try bindText(tab.title, to: statement, at: 5, database: database)
            try bindText(tab.url?.absoluteString, to: statement, at: 6, database: database)
            try bindText(tab.groupID?.uuidString, to: statement, at: 7, database: database)
            try bindOptionalInt(tab.navigationHistoryIndex, to: statement, at: 8, database: database)
            try bindOptionalBool(tab.isFavorite, to: statement, at: 9, database: database)
            try bindBool(tab.isPinned, to: statement, at: 10, database: database)
            try bindDate(tab.createdAt, to: statement, at: 11, database: database)
            try bindDate(tab.lastAccessedAt, to: statement, at: 12, database: database)
            try bindOptionalDouble(tab.pageZoom, to: statement, at: 13, database: database)
            try bindText(try tab.briefing.map { try encodeJSON($0.document) }, to: statement, at: 14, database: database)
            try bindText(try tab.briefing.map { try encodeJSON($0.phase) }, to: statement, at: 15, database: database)
            try stepDone(statement, database: database)
        }

        for (index, url) in (tab.navigationHistory ?? []).enumerated() {
            try insertNavigationEntry(url, forTabID: tab.id, sortOrder: index, in: database)
        }
        for (index, message) in (tab.briefing?.conversationHistory ?? []).enumerated() {
            try insertConversationMessage(
                message,
                into: "briefing_conversation_messages",
                ownerColumn: "tab_id",
                ownerID: tab.id.uuidString,
                sortOrder: index,
                in: database
            )
        }
    }

    private func insertNavigationEntry(
        _ url: URL,
        forTabID tabID: UUID,
        sortOrder: Int,
        in database: SQLiteDatabase
    ) throws {
        try database.prepare(
            """
            INSERT INTO navigation_entries (tab_id, sort_order, url)
            VALUES (?, ?, ?)
            """
        ) { statement in
            try bindText(tabID.uuidString, to: statement, at: 1, database: database)
            try bindInt(sortOrder, to: statement, at: 2, database: database)
            try bindText(url.absoluteString, to: statement, at: 3, database: database)
            try stepDone(statement, database: database)
        }
    }

    private func insertPageChat(
        _ pageChat: PersistedPageChatSnapshot,
        forWindowID windowID: UUID,
        in database: SQLiteDatabase
    ) throws {
        let chatID = "\(windowID.uuidString):\(pageChat.pageURL.chatSessionKey)"
        try database.prepare(
            """
            INSERT OR REPLACE INTO page_chats (id, window_id, page_url, page_title, updated_at, is_sidebar_visible)
            VALUES (?, ?, ?, ?, ?, ?)
            """
        ) { statement in
            try bindText(chatID, to: statement, at: 1, database: database)
            try bindText(windowID.uuidString, to: statement, at: 2, database: database)
            try bindText(pageChat.pageURL.absoluteString, to: statement, at: 3, database: database)
            try bindText(pageChat.pageTitle, to: statement, at: 4, database: database)
            try bindDate(pageChat.updatedAt, to: statement, at: 5, database: database)
            try bindOptionalBool(pageChat.isSidebarVisible, to: statement, at: 6, database: database)
            try stepDone(statement, database: database)
        }

        for (index, message) in pageChat.conversationHistory.enumerated() {
            try insertConversationMessage(
                message,
                into: "page_chat_messages",
                ownerColumn: "chat_id",
                ownerID: chatID,
                sortOrder: index,
                in: database
            )
        }
    }

    private func insertConversationMessage(
        _ message: ConversationMessage,
        into tableName: String,
        ownerColumn: String,
        ownerID: String,
        sortOrder: Int,
        in database: SQLiteDatabase
    ) throws {
        try database.prepare(
            """
            INSERT INTO \(tableName) (\(ownerColumn), sort_order, id, role, content, timestamp)
            VALUES (?, ?, ?, ?, ?, ?)
            """
        ) { statement in
            try bindText(ownerID, to: statement, at: 1, database: database)
            try bindInt(sortOrder, to: statement, at: 2, database: database)
            try bindText(message.id.uuidString, to: statement, at: 3, database: database)
            try bindText(message.role.rawValue, to: statement, at: 4, database: database)
            try bindText(message.content, to: statement, at: 5, database: database)
            try bindDate(message.timestamp, to: statement, at: 6, database: database)
            try stepDone(statement, database: database)
        }
    }

    private func deleteWindowState(forWindowID windowID: UUID, in database: SQLiteDatabase) throws {
        try database.prepare("DELETE FROM windows WHERE id = ?") { statement in
            try bindText(windowID.uuidString, to: statement, at: 1, database: database)
            try stepDone(statement, database: database)
        }
    }

    private func saveWorkspaceState(
        _ state: PersistedBrowserState,
        forWorkspaceID workspaceID: UUID,
        updatedAt: Date,
        in database: SQLiteDatabase,
        beginsTransaction: Bool = true
    ) throws {
        let work = {
            try ensureWorkspaceExists(workspaceID, in: database)
            try database.prepare(
                """
                INSERT OR REPLACE INTO workspace_states (workspace_id, state_json, updated_at)
                VALUES (?, ?, ?)
                """
            ) { statement in
                try bindText(workspaceID.uuidString, to: statement, at: 1, database: database)
                try bindText(try encodeJSON(state), to: statement, at: 2, database: database)
                try bindDate(updatedAt, to: statement, at: 3, database: database)
                try stepDone(statement, database: database)
            }
            try database.prepare("UPDATE workspaces SET updated_at = ? WHERE id = ?") { statement in
                try bindDate(updatedAt, to: statement, at: 1, database: database)
                try bindText(workspaceID.uuidString, to: statement, at: 2, database: database)
                try stepDone(statement, database: database)
            }
        }

        if beginsTransaction {
            try database.transaction(work)
        } else {
            try work()
        }
    }

    private func deleteWorkspaceState(forWorkspaceID workspaceID: UUID, in database: SQLiteDatabase) throws {
        try database.prepare("DELETE FROM workspace_states WHERE workspace_id = ?") { statement in
            try bindText(workspaceID.uuidString, to: statement, at: 1, database: database)
            try stepDone(statement, database: database)
        }
    }

    private func insertWorkspace(_ workspace: PersistedWorkspace, in database: SQLiteDatabase) throws {
        try database.prepare(
            """
            INSERT OR REPLACE INTO workspaces (
                id, name, created_at, updated_at, last_opened_at, color_name, icon_name, is_default
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """
        ) { statement in
            try bindText(workspace.id.uuidString, to: statement, at: 1, database: database)
            try bindText(workspace.name, to: statement, at: 2, database: database)
            try bindDate(workspace.createdAt, to: statement, at: 3, database: database)
            try bindDate(workspace.updatedAt, to: statement, at: 4, database: database)
            try bindOptionalDate(workspace.lastOpenedAt, to: statement, at: 5, database: database)
            try bindText(workspace.colorName, to: statement, at: 6, database: database)
            try bindText(workspace.iconName, to: statement, at: 7, database: database)
            try bindBool(workspace.isDefault, to: statement, at: 8, database: database)
            try stepDone(statement, database: database)
        }
    }

    private func ensureWorkspaceExists(_ workspaceID: UUID, in database: SQLiteDatabase) throws {
        if workspaceID == Self.defaultWorkspaceID {
            try ensureDefaultWorkspace(in: database)
            return
        }

        var exists = false
        try database.prepare("SELECT 1 FROM workspaces WHERE id = ?") { statement in
            try bindText(workspaceID.uuidString, to: statement, at: 1, database: database)
            exists = try stepRow(statement, database: database)
        }
        if !exists {
            let now = Date()
            try insertWorkspace(
                PersistedWorkspace(
                    id: workspaceID,
                    name: "Workspace",
                    createdAt: now,
                    updatedAt: now,
                    lastOpenedAt: nil,
                    colorName: nil,
                    iconName: nil,
                    isDefault: false
                ),
                in: database
            )
        }
    }

    private func ensureDefaultWorkspace(in database: SQLiteDatabase) throws {
        var exists = false
        try database.prepare("SELECT 1 FROM workspaces WHERE id = ?") { statement in
            try bindText(Self.defaultWorkspaceID.uuidString, to: statement, at: 1, database: database)
            exists = try stepRow(statement, database: database)
        }
        if !exists {
            try insertWorkspace(Self.defaultWorkspace(), in: database)
        }
    }

    private func setWindowWorkspaceID(_ workspaceID: UUID, forWindowID windowID: UUID, in database: SQLiteDatabase) throws {
        try database.prepare(
            """
            INSERT OR REPLACE INTO window_workspace_selection (window_id, workspace_id, updated_at)
            VALUES (?, ?, ?)
            """
        ) { statement in
            try bindText(windowID.uuidString, to: statement, at: 1, database: database)
            try bindText(workspaceID.uuidString, to: statement, at: 2, database: database)
            try bindDate(Date(), to: statement, at: 3, database: database)
            try stepDone(statement, database: database)
        }
        try database.prepare("UPDATE windows SET workspace_id = ? WHERE id = ?") { statement in
            try bindText(workspaceID.uuidString, to: statement, at: 1, database: database)
            try bindText(windowID.uuidString, to: statement, at: 2, database: database)
            try stepDone(statement, database: database)
        }
    }

    private static func defaultWorkspace() -> PersistedWorkspace {
        let now = Date()
        return PersistedWorkspace(
            id: defaultWorkspaceID,
            name: "Default",
            createdAt: now,
            updatedAt: now,
            lastOpenedAt: now,
            colorName: nil,
            iconName: "square.grid.2x2",
            isDefault: true
        )
    }

    private static func normalizedWorkspaceName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    // MARK: - Metadata

    private func metadataValue(forKey key: String, in database: SQLiteDatabase) throws -> String? {
        var value: String?
        try database.prepare("SELECT value FROM metadata WHERE key = ?") { statement in
            try bindText(key, to: statement, at: 1, database: database)
            if try stepRow(statement, database: database) {
                value = columnText(statement, at: 0)
            }
        }
        return value
    }

    private func setMetadataValue(_ value: String, forKey key: String, in database: SQLiteDatabase) throws {
        try database.prepare("INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)") { statement in
            try bindText(key, to: statement, at: 1, database: database)
            try bindText(value, to: statement, at: 2, database: database)
            try stepDone(statement, database: database)
        }
    }

    // MARK: - Legacy JSON

    private func loadLegacyState() -> PersistedBrowserState? {
        do {
            let data = try Data(contentsOf: fileURL)
            return try Self.makeJSONDecoder().decode(PersistedBrowserState.self, from: data)
        } catch {
            return nil
        }
    }

    private func loadLegacySession() -> PersistedBrowserWindowSession? {
        do {
            let data = try Data(contentsOf: sessionFileURL)
            return try Self.makeJSONDecoder().decode(PersistedBrowserWindowSession.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - JSON columns

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try Self.makeJSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SQLiteStoreError.encoding
        }
        return string
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        try Self.makeJSONDecoder().decode(type, from: Data(string.utf8))
    }

    private static func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Filesystem

    private func ensureDirectoryExists() throws {
        let directory = databaseURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func removeFileIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func databaseSidecarURL(suffix: String) -> URL {
        URL(fileURLWithPath: databaseURL.path + suffix)
    }

    private static func errorCategory(_ error: Error) -> String {
        if let error = error as? SQLiteStoreError {
            return error.category
        }
        if let cocoaError = error as? CocoaError {
            return "cocoa-\(cocoaError.errorCode)"
        }
        if let posixError = error as? POSIXError {
            return "posix-\(posixError.code.rawValue)"
        }
        return "unknown"
    }
}

private struct WindowRow {
    let activeTabID: UUID?
    let isTabBarVisible: Bool
    let tabBarWidth: Double
    let chatPaneWidth: Double?
    let chatPaneHeight: Double?
    let chatPaneOffsetX: Double?
    let chatPaneOffsetY: Double?
}

private struct TabRow {
    let id: UUID
    let kind: TabKind
    let title: String
    let url: URL?
    let groupID: UUID?
    let navigationHistoryIndex: Int?
    let isFavorite: Bool?
    let isPinned: Bool
    let createdAt: Date
    let lastAccessedAt: Date
    let briefingDocumentJSON: String?
    let briefingPhaseJSON: String?
    let pageZoom: Double?
}

private struct PageChatRow {
    let id: String
    let pageURL: URL
    let pageTitle: String
    let updatedAt: Date
    let isSidebarVisible: Bool?
}

private struct PersistedWorkspaceStateSnapshot {
    let workspaceID: UUID
    let state: PersistedBrowserState
    let updatedAt: Date
}

private final class SQLiteDatabase {
    let handle: OpaquePointer

    init(url: URL) throws {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(url.path, &database, flags, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let database {
                sqlite3_close(database)
            }
            throw SQLiteStoreError.open(message)
        }

        self.handle = database
        sqlite3_busy_timeout(handle, 2_500)
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: UnsafePointer($0)) } ?? lastErrorMessage
            sqlite3_free(errorMessage)
            throw SQLiteStoreError.sqlite(message)
        }
    }

    func prepare<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw SQLiteStoreError.sqlite(lastErrorMessage)
        }
        defer {
            sqlite3_finalize(statement)
        }
        return try body(statement)
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    var lastErrorMessage: String {
        String(cString: sqlite3_errmsg(handle))
    }
}

private enum SQLiteStoreError: Error {
    case open(String)
    case sqlite(String)
    case encoding
    case step(String)

    var category: String {
        switch self {
        case .open:
            return "sqlite-open"
        case .sqlite:
            return "sqlite"
        case .encoding:
            return "sqlite-encoding"
        case .step:
            return "sqlite-step"
        }
    }
}

private func bindText(_ value: String?, to statement: OpaquePointer, at index: Int32, database: SQLiteDatabase) throws {
    let result: Int32
    if let value {
        result = value.withCString {
            sqlite3_bind_text(statement, index, $0, -1, sqliteTransient)
        }
    } else {
        result = sqlite3_bind_null(statement, index)
    }
    try checkBindResult(result, database: database)
}

private func bindInt(_ value: Int, to statement: OpaquePointer, at index: Int32, database: SQLiteDatabase) throws {
    try checkBindResult(sqlite3_bind_int64(statement, index, sqlite3_int64(value)), database: database)
}

private func bindOptionalInt(_ value: Int?, to statement: OpaquePointer, at index: Int32, database: SQLiteDatabase) throws {
    if let value {
        try bindInt(value, to: statement, at: index, database: database)
    } else {
        try checkBindResult(sqlite3_bind_null(statement, index), database: database)
    }
}

private func bindBool(_ value: Bool, to statement: OpaquePointer, at index: Int32, database: SQLiteDatabase) throws {
    try bindInt(value ? 1 : 0, to: statement, at: index, database: database)
}

private func bindOptionalBool(_ value: Bool?, to statement: OpaquePointer, at index: Int32, database: SQLiteDatabase) throws {
    if let value {
        try bindBool(value, to: statement, at: index, database: database)
    } else {
        try checkBindResult(sqlite3_bind_null(statement, index), database: database)
    }
}

private func bindDouble(_ value: Double, to statement: OpaquePointer, at index: Int32, database: SQLiteDatabase) throws {
    try checkBindResult(sqlite3_bind_double(statement, index, value), database: database)
}

private func bindOptionalDouble(_ value: Double?, to statement: OpaquePointer, at index: Int32, database: SQLiteDatabase) throws {
    if let value {
        try bindDouble(value, to: statement, at: index, database: database)
    } else {
        try checkBindResult(sqlite3_bind_null(statement, index), database: database)
    }
}

private func bindDate(_ value: Date, to statement: OpaquePointer, at index: Int32, database: SQLiteDatabase) throws {
    try bindDouble(value.timeIntervalSince1970, to: statement, at: index, database: database)
}

private func bindOptionalDate(_ value: Date?, to statement: OpaquePointer, at index: Int32, database: SQLiteDatabase) throws {
    if let value {
        try bindDate(value, to: statement, at: index, database: database)
    } else {
        try checkBindResult(sqlite3_bind_null(statement, index), database: database)
    }
}

private func stepDone(_ statement: OpaquePointer, database: SQLiteDatabase) throws {
    let result = sqlite3_step(statement)
    guard result == SQLITE_DONE else {
        throw SQLiteStoreError.step(database.lastErrorMessage)
    }
}

private func stepRow(_ statement: OpaquePointer, database: SQLiteDatabase) throws -> Bool {
    let result = sqlite3_step(statement)
    if result == SQLITE_ROW {
        return true
    }
    if result == SQLITE_DONE {
        return false
    }
    throw SQLiteStoreError.step(database.lastErrorMessage)
}

private func checkBindResult(_ result: Int32, database: SQLiteDatabase) throws {
    guard result == SQLITE_OK else {
        throw SQLiteStoreError.sqlite(database.lastErrorMessage)
    }
}

private func columnText(_ statement: OpaquePointer, at index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL,
          let text = sqlite3_column_text(statement, index) else {
        return nil
    }
    return String(cString: UnsafeRawPointer(text).assumingMemoryBound(to: CChar.self))
}

private func columnDouble(_ statement: OpaquePointer, at index: Int32) -> Double {
    sqlite3_column_double(statement, index)
}

private func columnOptionalDouble(_ statement: OpaquePointer, at index: Int32) -> Double? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    return columnDouble(statement, at: index)
}

private func columnInt(_ statement: OpaquePointer, at index: Int32) -> Int {
    Int(sqlite3_column_int64(statement, index))
}

private func columnOptionalInt(_ statement: OpaquePointer, at index: Int32) -> Int? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    return columnInt(statement, at: index)
}

private func columnBool(_ statement: OpaquePointer, at index: Int32) -> Bool {
    sqlite3_column_int(statement, index) != 0
}

private func columnOptionalBool(_ statement: OpaquePointer, at index: Int32) -> Bool? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    return columnBool(statement, at: index)
}

private func columnDate(_ statement: OpaquePointer, at index: Int32) -> Date {
    Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
}

private func columnOptionalDate(_ statement: OpaquePointer, at index: Int32) -> Date? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    return columnDate(statement, at: index)
}

extension PersistedBrowserState {
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

    /// Splits out favorite tabs, returning the state without them plus the
    /// extracted favorite snapshots. Used to migrate legacy per-workspace
    /// favorites into the shared global set.
    func removingFavoriteTabs() -> (state: PersistedBrowserState, favorites: [PersistedTabSnapshot]) {
        let favorites = tabs.filter { $0.isFavorite == true }
        guard !favorites.isEmpty else { return (self, []) }

        let remainingTabs = tabs.filter { $0.isFavorite != true }
        let state = PersistedBrowserState(
            tabs: remainingTabs,
            tabGroups: tabGroups,
            activeTabID: activeTabID.flatMap { id in
                remainingTabs.contains { $0.id == id } ? id : remainingTabs.first?.id
            },
            isTabBarVisible: isTabBarVisible,
            tabBarWidth: tabBarWidth,
            chatPaneWidth: chatPaneWidth,
            chatPaneHeight: chatPaneHeight,
            chatPaneOffsetX: chatPaneOffsetX,
            chatPaneOffsetY: chatPaneOffsetY,
            pageChats: pageChats
        )
        return (state, favorites)
    }

    /// Returns a copy with freshly generated tab and tab-group identifiers.
    /// Tab IDs are the primary key of the shared `tabs` table, so a workspace
    /// snapshot applied to a second window must not reuse the IDs already
    /// persisted by the first window — the insert would conflict and roll back
    /// that window's entire persist transaction.
    func withRegeneratedTabIdentity() -> PersistedBrowserState {
        var groupIDMap: [UUID: UUID] = [:]
        let regeneratedGroups = tabGroups.map { groups in
            groups.map { group -> PersistedTabGroupSnapshot in
                let newID = UUID()
                groupIDMap[group.id] = newID
                return PersistedTabGroupSnapshot(
                    id: newID,
                    title: group.title,
                    isCollapsed: group.isCollapsed,
                    createdAt: group.createdAt
                )
            }
        }

        var tabIDMap: [UUID: UUID] = [:]
        let regeneratedTabs = tabs.map { tab -> PersistedTabSnapshot in
            let newID = UUID()
            tabIDMap[tab.id] = newID
            return PersistedTabSnapshot(
                id: newID,
                kind: tab.kind,
                title: tab.title,
                url: tab.url,
                groupID: tab.groupID.flatMap { groupIDMap[$0] },
                navigationHistory: tab.navigationHistory,
                navigationHistoryIndex: tab.navigationHistoryIndex,
                pageZoom: tab.pageZoom,
                isFavorite: tab.isFavorite,
                isPinned: tab.isPinned,
                createdAt: tab.createdAt,
                lastAccessedAt: tab.lastAccessedAt,
                briefing: tab.briefing
            )
        }

        return PersistedBrowserState(
            tabs: regeneratedTabs,
            tabGroups: regeneratedGroups,
            activeTabID: activeTabID.flatMap { tabIDMap[$0] },
            isTabBarVisible: isTabBarVisible,
            tabBarWidth: tabBarWidth,
            chatPaneWidth: chatPaneWidth,
            chatPaneHeight: chatPaneHeight,
            chatPaneOffsetX: chatPaneOffsetX,
            chatPaneOffsetY: chatPaneOffsetY,
            pageChats: pageChats
        )
    }
}

private extension PersistedBrowserState {
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

extension PersistedTabSnapshot {
    /// Key used to deduplicate favorites when merging per-workspace favorites
    /// into the shared global set.
    var favoriteDedupeKey: String {
        url?.absoluteString ?? "\(kind.rawValue):\(title)"
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
            pageZoom: pageZoom,
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
