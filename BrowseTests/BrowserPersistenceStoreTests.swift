import Foundation
import Testing
@testable import Browse

@Suite("BrowserPersistenceStore")
struct BrowserPersistenceStoreTests {
    @Test("saves and removes independent window states")
    func savesAndRemovesIndependentWindowStates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let firstWindowID = UUID()
        let secondWindowID = UUID()
        let firstState = makeState(tabTitle: "First", url: URL(string: "https://example.com/first"))
        let secondState = makeState(tabTitle: "Second", url: URL(string: "https://example.com/second"))

        store.save(firstState, forWindowID: firstWindowID)
        store.save(secondState, forWindowID: secondWindowID)

        #expect(store.loadWindowState(forWindowID: firstWindowID)?.tabs.first?.title == "First")
        #expect(store.loadWindowState(forWindowID: secondWindowID)?.tabs.first?.title == "Second")
        #expect(Set(store.loadRestorableWindowIDs()) == Set([firstWindowID, secondWindowID]))

        store.removeWindowState(forWindowID: firstWindowID)

        #expect(store.loadWindowState(forWindowID: firstWindowID) == nil)
        #expect(store.loadRestorableWindowIDs() == [secondWindowID])
    }

    @Test("does not restore blank new tab windows")
    func doesNotRestoreBlankNewTabWindows() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let windowID = UUID()

        store.save(makeState(tabTitle: "New Tab", url: nil), forWindowID: windowID)

        #expect(store.loadWindowState(forWindowID: windowID) == nil)
        #expect(store.loadRestorableWindowIDs().isEmpty)
    }

    @Test("prunes restore list to currently open meaningful windows")
    func prunesRestoreListToOpenMeaningfulWindows() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let openWindowID = UUID()
        let closedWindowID = UUID()

        store.save(makeState(tabTitle: "Open", url: URL(string: "https://example.com/open")), forWindowID: openWindowID)
        store.save(makeState(tabTitle: "Closed", url: URL(string: "https://example.com/closed")), forWindowID: closedWindowID)

        store.pruneWindowStates(keepingWindowIDs: [openWindowID])

        #expect(store.loadRestorableWindowIDs() == [openWindowID])
        #expect(store.loadWindowState(forWindowID: closedWindowID) == nil)
    }

    @Test("clears AI history while preserving tabs")
    func clearsAIHistoryWhilePreservingTabs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let windowID = UUID()
        store.save(makeStateWithAIHistory(), forWindowID: windowID)

        try store.clearAIHistory()

        let state = try #require(store.loadWindowState(forWindowID: windowID))
        #expect(state.tabs.count == 2)
        #expect(state.pageChats == nil)
        #expect(state.tabs.first { $0.kind == .briefing }?.briefing?.conversationHistory.isEmpty == true)
    }

    @Test("clears AI history from workspace states")
    func clearsAIHistoryFromWorkspaceStates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let workspace = store.createWorkspace(name: "AI")
        store.save(makeStateWithAIHistory(), forWindowID: UUID(), workspaceID: workspace.id)

        try store.clearAIHistory()

        let state = try #require(store.loadWorkspaceState(forWorkspaceID: workspace.id))
        #expect(state.pageChats == nil)
        #expect(state.tabs.first { $0.kind == .briefing }?.briefing?.conversationHistory.isEmpty == true)
    }

    @Test("saves session data in SQLite")
    func savesSessionDataInSQLite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let windowID = UUID()

        store.save(makeState(tabTitle: "SQLite", url: URL(string: "https://example.com/sqlite")), forWindowID: windowID)

        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("browser.sqlite").path))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("browser-session.json").path))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("browser-state.json").path))
        #expect(store.loadWindowState(forWindowID: windowID)?.tabs.first?.title == "SQLite")
    }

    @Test("saves and restores AI history from SQLite")
    func savesAndRestoresAIHistoryFromSQLite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let windowID = UUID()
        store.save(makeStateWithAIHistory(), forWindowID: windowID)

        let state = try #require(store.loadWindowState(forWindowID: windowID))
        #expect(state.pageChats?.first?.conversationHistory.first?.content == "Question")
        #expect(state.tabs.first { $0.kind == .briefing }?.briefing?.conversationHistory.first?.content == "Question")
    }

    @Test("migrates legacy JSON sessions into SQLite")
    func migratesLegacyJSONSessionsIntoSQLite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let windowID = UUID()
        let session = PersistedBrowserWindowSession(
            windows: [
                PersistedBrowserWindowSnapshot(
                    id: windowID,
                    state: makeStateWithAIHistory(),
                    lastUpdatedAt: Date(timeIntervalSince1970: 1_000)
                )
            ]
        )
        try writeLegacyJSON(session, to: directory.appendingPathComponent("browser-session.json"))

        let store = BrowserPersistenceStore(directoryURL: directory)
        let state = try #require(store.loadWindowState(forWindowID: windowID))

        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("browser.sqlite").path))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("browser-session.json").path))
        #expect(state.tabs.count == 2)
        #expect(state.pageChats?.first?.conversationHistory.first?.content == "Question")
        #expect(state.tabs.first { $0.kind == .briefing }?.briefing?.conversationHistory.first?.content == "Question")
    }

    @Test("creates default workspace and associates existing windows")
    func createsDefaultWorkspaceAndAssociatesExistingWindows() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let windowID = UUID()
        let state = makeState(tabTitle: "Workspace", url: URL(string: "https://example.com/workspace"))

        store.save(state, forWindowID: windowID)

        let workspaces = store.loadWorkspaces()
        #expect(workspaces.count == 1)
        #expect(workspaces.first?.isDefault == true)
        #expect(store.workspaceID(forWindowID: windowID) == BrowserPersistenceStore.defaultWorkspaceID)
        #expect(store.loadWorkspaceState(forWorkspaceID: BrowserPersistenceStore.defaultWorkspaceID)?.tabs.first?.title == "Workspace")
    }

    @Test("saves independent workspace states")
    func savesIndependentWorkspaceStates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let windowID = UUID()
        let first = store.createWorkspace(name: "First")
        let second = store.createWorkspace(name: "Second")

        store.save(
            makeState(tabTitle: "First", url: URL(string: "https://example.com/first")),
            forWindowID: windowID,
            workspaceID: first.id
        )
        store.save(
            makeState(tabTitle: "Second", url: URL(string: "https://example.com/second")),
            forWindowID: windowID,
            workspaceID: second.id
        )

        #expect(store.loadWorkspaceState(forWorkspaceID: first.id)?.tabs.first?.title == "First")
        #expect(store.loadWorkspaceState(forWorkspaceID: second.id)?.tabs.first?.title == "Second")
    }

    @Test("deleting a workspace preserves default workspace")
    func deletingWorkspacePreservesDefaultWorkspace() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let workspace = store.createWorkspace(name: "Temporary")
        store.save(
            makeState(tabTitle: "Temporary", url: URL(string: "https://example.com/temp")),
            forWindowID: UUID(),
            workspaceID: workspace.id
        )

        store.deleteWorkspace(workspace.id)

        #expect(!store.loadWorkspaces().contains { $0.id == workspace.id })
        #expect(store.loadWorkspaceState(forWorkspaceID: workspace.id) == nil)
        #expect(store.loadWorkspaces().contains { $0.id == BrowserPersistenceStore.defaultWorkspaceID })
    }

    @Test("clears persisted browsing data files")
    func clearsPersistedBrowsingDataFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let windowID = UUID()
        store.save(makeState(tabTitle: "Window", url: URL(string: "https://example.com")), forWindowID: windowID)

        try store.clearBrowsingData()

        #expect(store.loadWindowState(forWindowID: windowID) == nil)
        #expect(store.loadRestorableWindowIDs().isEmpty)
    }

    @Test("prunes browsing data older than cutoff")
    func prunesBrowsingDataOlderThanCutoff() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let oldWindowID = UUID()
        let recentWindowID = UUID()
        let oldDate = Date(timeIntervalSince1970: 100)
        let recentDate = Date(timeIntervalSince1970: 1_000)

        store.save(
            makeState(tabTitle: "Old", url: URL(string: "https://example.com/old"), lastAccessedAt: oldDate),
            forWindowID: oldWindowID
        )
        store.save(
            makeState(tabTitle: "Recent", url: URL(string: "https://example.com/recent"), lastAccessedAt: recentDate),
            forWindowID: recentWindowID
        )

        try store.pruneBrowsingData(olderThan: Date(timeIntervalSince1970: 500))

        #expect(store.loadWindowState(forWindowID: oldWindowID) == nil)
        #expect(store.loadWindowState(forWindowID: recentWindowID)?.tabs.first?.title == "Recent")
    }

    @Test("saves tab group metadata and tab membership")
    func savesTabGroupMetadataAndTabMembership() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let windowID = UUID()
        let groupID = UUID()
        let url = URL(string: "https://example.com/grouped")!
        let state = PersistedBrowserState(
            tabs: [
                PersistedTabSnapshot(
                    id: UUID(),
                    kind: .web,
                    title: "Grouped",
                    url: url,
                    groupID: groupID,
                    navigationHistory: [url],
                    navigationHistoryIndex: 0,
                    isFavorite: false,
                    isPinned: false,
                    createdAt: Date(),
                    lastAccessedAt: Date(),
                    briefing: nil
                )
            ],
            tabGroups: [
                PersistedTabGroupSnapshot(
                    id: groupID,
                    title: "Research",
                    isCollapsed: true,
                    createdAt: Date()
                )
            ],
            activeTabID: nil,
            isTabBarVisible: true,
            tabBarWidth: 220,
            chatPaneWidth: nil,
            chatPaneHeight: nil,
            chatPaneOffsetX: nil,
            chatPaneOffsetY: nil,
            pageChats: nil
        )

        store.save(state, forWindowID: windowID)

        let loadedState = try #require(store.loadWindowState(forWindowID: windowID))
        #expect(loadedState.tabGroups?.first?.id == groupID)
        #expect(loadedState.tabGroups?.first?.title == "Research")
        #expect(loadedState.tabGroups?.first?.isCollapsed == true)
        #expect(loadedState.tabs.first?.groupID == groupID)
    }

    @Test("saves and restores web tab page zoom")
    func savesAndRestoresWebTabPageZoom() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let windowID = UUID()
        let url = URL(string: "https://example.com/zoom")!
        let state = PersistedBrowserState(
            tabs: [
                PersistedTabSnapshot(
                    id: UUID(),
                    kind: .web,
                    title: "Zoomed",
                    url: url,
                    navigationHistory: [url],
                    navigationHistoryIndex: 0,
                    pageZoom: 1.25,
                    isFavorite: false,
                    isPinned: false,
                    createdAt: Date(),
                    lastAccessedAt: Date(),
                    briefing: nil
                ),
                PersistedTabSnapshot(
                    id: UUID(),
                    kind: .briefing,
                    title: "Briefing",
                    url: nil,
                    navigationHistory: nil,
                    navigationHistoryIndex: nil,
                    isFavorite: false,
                    isPinned: false,
                    createdAt: Date(),
                    lastAccessedAt: Date(),
                    briefing: nil
                )
            ],
            activeTabID: nil,
            isTabBarVisible: true,
            tabBarWidth: 220,
            chatPaneWidth: nil,
            chatPaneHeight: nil,
            chatPaneOffsetX: nil,
            chatPaneOffsetY: nil,
            pageChats: nil
        )

        store.save(state, forWindowID: windowID)

        let loadedState = try #require(store.loadWindowState(forWindowID: windowID))
        #expect(loadedState.tabs.first { $0.kind == .web }?.pageZoom == 1.25)
        #expect(loadedState.tabs.first { $0.kind == .briefing }?.pageZoom == nil)
    }

    private func makeState(
        tabTitle: String,
        url: URL?,
        lastAccessedAt: Date = Date()
    ) -> PersistedBrowserState {
        PersistedBrowserState(
            tabs: [
                PersistedTabSnapshot(
                    id: UUID(),
                    kind: .web,
                    title: tabTitle,
                    url: url,
                    navigationHistory: url.map { [$0] },
                    navigationHistoryIndex: nil,
                    isFavorite: false,
                    isPinned: false,
                    createdAt: Date(),
                    lastAccessedAt: lastAccessedAt,
                    briefing: nil
                )
            ],
            activeTabID: nil,
            isTabBarVisible: true,
            tabBarWidth: 220,
            chatPaneWidth: nil,
            chatPaneHeight: nil,
            chatPaneOffsetX: nil,
            chatPaneOffsetY: nil,
            pageChats: nil
        )
    }

    private func makeStateWithAIHistory() -> PersistedBrowserState {
        PersistedBrowserState(
            tabs: [
                PersistedTabSnapshot(
                    id: UUID(),
                    kind: .web,
                    title: "Example",
                    url: URL(string: "https://example.com"),
                    navigationHistory: [URL(string: "https://example.com")!],
                    navigationHistoryIndex: 0,
                    isFavorite: false,
                    isPinned: false,
                    createdAt: Date(),
                    lastAccessedAt: Date(),
                    briefing: nil
                ),
                PersistedTabSnapshot(
                    id: UUID(),
                    kind: .briefing,
                    title: "Briefing",
                    url: nil,
                    navigationHistory: nil,
                    navigationHistoryIndex: nil,
                    isFavorite: false,
                    isPinned: false,
                    createdAt: Date(),
                    lastAccessedAt: Date(),
                    briefing: PersistedBriefingSnapshot(
                        document: BriefingDocument(query: "Briefing"),
                        phase: .complete,
                        conversationHistory: [
                            ConversationMessage(role: .user, content: "Question")
                        ]
                    )
                )
            ],
            activeTabID: nil,
            isTabBarVisible: true,
            tabBarWidth: 220,
            chatPaneWidth: nil,
            chatPaneHeight: nil,
            chatPaneOffsetX: nil,
            chatPaneOffsetY: nil,
            pageChats: [
                PersistedPageChatSnapshot(
                    pageURL: URL(string: "https://example.com")!,
                    pageTitle: "Example",
                    conversationHistory: [
                        ConversationMessage(role: .user, content: "Question")
                    ],
                    updatedAt: Date(),
                    isSidebarVisible: nil
                )
            ]
        )
    }

    private func writeLegacyJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }
}
