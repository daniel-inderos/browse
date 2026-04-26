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

    private func makeState(tabTitle: String, url: URL?) -> PersistedBrowserState {
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
    }
}
