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
                    updatedAt: Date()
                )
            ]
        )
    }
}
