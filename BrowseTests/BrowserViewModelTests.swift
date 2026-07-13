import Foundation
import Testing
@testable import Browse

@MainActor
@Suite("BrowserViewModel")
struct BrowserViewModelTests {
    @Test("Command number selection follows visible tab sections")
    func commandNumberSelectionFollowsVisibleTabSections() {
        let viewModel = makeViewModel()
        let earlierDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        let today = Tab(kind: .web, title: "Today")
        let favorite = Tab(kind: .web, title: "Favorite", isFavorite: true)
        let pinned = Tab(kind: .web, title: "Pinned", isPinned: true)
        let earlier = Tab(kind: .web, title: "Earlier", lastAccessedAt: earlierDate)

        viewModel.tabs = [today, favorite, earlier, pinned]
        viewModel.activeTabID = today.id

        viewModel.selectTabByIndex(0)
        #expect(viewModel.activeTabID == favorite.id)

        viewModel.selectTabByIndex(1)
        #expect(viewModel.activeTabID == pinned.id)

        viewModel.selectTabByIndex(2)
        #expect(viewModel.activeTabID == today.id)

        viewModel.selectLastTab()
        #expect(viewModel.activeTabID == earlier.id)
    }

    @Test("Command number selection includes tab groups before ungrouped tabs")
    func commandNumberSelectionIncludesTabGroupsBeforeUngroupedTabs() {
        let viewModel = makeViewModel()
        let group = TabGroup(title: "Work")
        let earlierDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        let today = Tab(kind: .web, title: "Today")
        let groupedFirst = Tab(kind: .web, title: "Grouped First", groupID: group.id)
        let earlier = Tab(kind: .web, title: "Earlier", lastAccessedAt: earlierDate)
        let groupedSecond = Tab(kind: .web, title: "Grouped Second", groupID: group.id)

        viewModel.tabGroups = [group]
        viewModel.tabs = [today, groupedFirst, earlier, groupedSecond]
        viewModel.activeTabID = today.id

        viewModel.selectTabByIndex(0)
        #expect(viewModel.activeTabID == groupedFirst.id)

        viewModel.selectTabByIndex(1)
        #expect(viewModel.activeTabID == groupedSecond.id)

        viewModel.selectTabByIndex(2)
        #expect(viewModel.activeTabID == today.id)

        viewModel.selectLastTab()
        #expect(viewModel.activeTabID == earlier.id)
    }

    @Test("Deleting a tab group keeps tabs open and clears membership")
    func deletingTabGroupKeepsTabsOpenAndClearsMembership() throws {
        let viewModel = makeViewModel()
        let tab = try #require(viewModel.activeTab)

        let groupID = viewModel.createTabGroup(title: "Read Later", containing: tab.id)
        #expect(viewModel.tabGroups.count == 1)
        #expect(tab.groupID == groupID)

        viewModel.deleteTabGroup(groupID)

        #expect(viewModel.tabGroups.isEmpty)
        #expect(viewModel.tabs.map(\.id).contains(tab.id))
        #expect(tab.groupID == nil)
    }

    @Test("Closing the last tab in a group deletes the group")
    func closingLastTabInGroupDeletesGroup() throws {
        let viewModel = makeViewModel()
        let firstTab = try #require(viewModel.activeTab)
        let groupID = viewModel.createTabGroup(title: "Research", containing: firstTab.id)

        viewModel.newTab()
        let secondTab = try #require(viewModel.activeTab)
        viewModel.moveTab(secondTab.id, toGroup: groupID)

        viewModel.closeTab(firstTab.id)
        #expect(viewModel.tabGroups.map(\.id).contains(groupID))

        viewModel.closeTab(secondTab.id)
        #expect(!viewModel.tabGroups.map(\.id).contains(groupID))
    }

    @Test("Moving a tab into a collapsed group expands it")
    func movingTabIntoCollapsedGroupExpandsIt() throws {
        let viewModel = makeViewModel()
        let tab = try #require(viewModel.activeTab)
        let groupID = viewModel.createTabGroup(title: "Research")

        viewModel.toggleTabGroupCollapsed(groupID)
        #expect(viewModel.tabGroups.first?.isCollapsed == true)

        viewModel.moveTab(tab.id, toGroup: groupID)

        #expect(viewModel.tabGroups.first?.isCollapsed == false)
        #expect(tab.groupID == groupID)
    }

    @Test("Active tab URL uses live page URL before stored URL")
    func activeTabURLUsesLivePageURLBeforeStoredURL() throws {
        let viewModel = makeViewModel()
        let tab = try #require(viewModel.activeTab)
        let webVM = try #require(tab.webTabViewModel)

        tab.url = URL(string: "https://example.com/stored")
        #expect(viewModel.activeTabURL == tab.url)

        webVM.currentURL = URL(string: "https://example.com/live")
        #expect(viewModel.activeTabURL == webVM.currentURL)
    }

    @Test("Copy URL indicator becomes visible")
    func copyURLIndicatorBecomesVisible() {
        let viewModel = makeViewModel()

        #expect(!viewModel.isCurrentURLCopyIndicatorVisible)
        viewModel.showCurrentURLCopiedIndicator()
        #expect(viewModel.isCurrentURLCopyIndicatorVisible)
    }

    @Test("Find in page is available only for loaded web tabs")
    func findInPageIsAvailableOnlyForLoadedWebTabs() throws {
        let viewModel = makeViewModel()
        let webTab = try #require(viewModel.activeTab)
        let webVM = try #require(webTab.webTabViewModel)

        #expect(!viewModel.canFindInActiveTab)
        viewModel.showFindInActiveTab()
        #expect(!webVM.isFindBarVisible)

        webVM.currentURL = URL(string: "https://example.com")
        #expect(viewModel.canFindInActiveTab)

        viewModel.isIntentBarVisible = false
        viewModel.showFindInActiveTab()
        #expect(webVM.isFindBarVisible)
        #expect(viewModel.isFindBarVisibleInActiveTab)
        #expect(viewModel.isIntentBarVisible)

        let briefingTab = Tab(kind: .briefing, title: "Briefing")
        viewModel.tabs.append(briefingTab)
        viewModel.activeTabID = briefingTab.id

        #expect(!viewModel.canFindInActiveTab)
        viewModel.showFindInActiveTab()
        #expect(!viewModel.isFindBarVisibleInActiveTab)
    }

    @Test("Page zoom is scoped to web tabs and ignored by briefing tabs")
    func pageZoomIsScopedToWebTabsAndIgnoredByBriefingTabs() throws {
        let viewModel = makeViewModel()
        let firstTab = try #require(viewModel.activeTab)
        let firstWebVM = try #require(firstTab.webTabViewModel)

        #expect(!viewModel.isPageZoomIndicatorVisible)
        viewModel.zoomInActiveTab()
        #expect(firstWebVM.pageZoom == 1.1)
        #expect(firstTab.pageZoom == 1.1)
        #expect(viewModel.activePageZoomDisplayText == "110%")
        #expect(viewModel.isPageZoomIndicatorVisible)
        #expect(viewModel.pageZoomIndicatorText == "110%")
        #expect(viewModel.canResetZoomInActiveTab)

        viewModel.newTab()
        let secondTab = try #require(viewModel.activeTab)
        let secondWebVM = try #require(secondTab.webTabViewModel)
        #expect(secondWebVM.pageZoom == WebTabViewModel.defaultPageZoom)

        viewModel.selectTab(firstTab.id)
        #expect(firstWebVM.pageZoom == 1.1)
        viewModel.resetZoomInActiveTab()
        #expect(firstWebVM.pageZoom == WebTabViewModel.defaultPageZoom)
        #expect(firstTab.pageZoom == nil)
        #expect(viewModel.pageZoomIndicatorText == "100%")

        let briefingTab = Tab(kind: .briefing, title: "Briefing")
        viewModel.tabs.append(briefingTab)
        viewModel.selectTab(briefingTab.id)

        #expect(viewModel.activePageZoomDisplayText == nil)
        #expect(!viewModel.canZoomInActiveTab)
        viewModel.zoomInActiveTab()
        #expect(secondWebVM.pageZoom == WebTabViewModel.defaultPageZoom)
    }

    @Test("Page chat sidebar visibility follows the active page")
    func pageChatSidebarVisibilityFollowsActivePage() throws {
        let viewModel = makeViewModel()
        let firstTab = try #require(viewModel.activeTab)
        let firstWebVM = try #require(firstTab.webTabViewModel)
        firstWebVM.currentURL = URL(string: "https://example.com/first")
        firstWebVM.pageTitle = "First"

        viewModel.openChatPane()

        let firstChatVM = try #require(viewModel.chatViewModel)
        #expect(viewModel.isChatPaneVisible)

        viewModel.newTab()
        let secondTab = try #require(viewModel.activeTab)
        let secondWebVM = try #require(secondTab.webTabViewModel)
        secondWebVM.currentURL = URL(string: "https://example.com/second")
        secondWebVM.pageTitle = "Second"
        viewModel.selectTab(secondTab.id)

        #expect(!viewModel.isChatPaneVisible)
        #expect(viewModel.chatViewModel == nil)

        viewModel.openChatPane()

        let secondChatVM = try #require(viewModel.chatViewModel)
        #expect(viewModel.isChatPaneVisible)

        viewModel.selectTab(firstTab.id)
        #expect(viewModel.isChatPaneVisible)
        #expect(viewModel.chatViewModel === firstChatVM)

        viewModel.selectTab(secondTab.id)
        #expect(viewModel.isChatPaneVisible)
        #expect(viewModel.chatViewModel === secondChatVM)

        viewModel.closeChatPane()
        #expect(!viewModel.isChatPaneVisible)

        viewModel.selectTab(firstTab.id)
        #expect(viewModel.isChatPaneVisible)
        #expect(viewModel.chatViewModel === firstChatVM)

        viewModel.selectTab(secondTab.id)
        #expect(!viewModel.isChatPaneVisible)
        #expect(viewModel.chatViewModel == nil)
    }

    @Test("Reopening a closed web tab creates a fresh web view")
    func reopeningClosedWebTabCreatesFreshWebView() throws {
        let viewModel = makeViewModel()
        let tab = try #require(viewModel.activeTab)
        let originalWebVM = try #require(tab.webTabViewModel)
        let previousURL = try #require(URL(string: "https://example.com/previous"))
        let url = try #require(URL(string: "https://example.com/article"))

        tab.url = url
        originalWebVM.currentURL = url
        originalWebVM.pageTitle = "Example Article"
        originalWebVM.setPageZoom(1.25)
        originalWebVM.restoreNavigationHistory([previousURL, url], currentIndex: 1)

        viewModel.closeTab(tab.id)

        #expect(tab.webTabViewModel == nil)
        #expect(originalWebVM.currentURL == nil)
        #expect(!originalWebVM.isLoading)

        viewModel.reopenLastClosedTab()

        let reopenedTab = try #require(viewModel.activeTab)
        let reopenedWebVM = try #require(reopenedTab.webTabViewModel)

        #expect(reopenedTab.url == url)
        #expect(reopenedTab.title == "Example Article")
        #expect(reopenedWebVM !== originalWebVM)
        #expect(reopenedWebVM.navigationHistorySnapshot == [previousURL, url])
        #expect(reopenedWebVM.navigationHistorySnapshotIndex == 1)
        #expect(reopenedWebVM.pageZoom == 1.25)
    }

    @Test("Restores persisted SQLite window state")
    func restoresPersistedSQLiteWindowState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let windowID = UUID()
        let webTabID = UUID()
        let briefingTabID = UUID()
        let previousURL = try #require(URL(string: "https://example.com/previous"))
        let currentURL = try #require(URL(string: "https://example.com/current"))
        let message = ConversationMessage(role: .user, content: "What changed?")
        let state = PersistedBrowserState(
            tabs: [
                PersistedTabSnapshot(
                    id: webTabID,
                    kind: .web,
                    title: "Current",
                    url: currentURL,
                    navigationHistory: [previousURL, currentURL],
                    navigationHistoryIndex: 1,
                    pageZoom: 1.25,
                    isFavorite: false,
                    isPinned: false,
                    createdAt: Date(timeIntervalSince1970: 1_000),
                    lastAccessedAt: Date(timeIntervalSince1970: 2_000),
                    briefing: nil
                ),
                PersistedTabSnapshot(
                    id: briefingTabID,
                    kind: .briefing,
                    title: "SQLite briefing",
                    url: nil,
                    navigationHistory: nil,
                    navigationHistoryIndex: nil,
                    isFavorite: false,
                    isPinned: false,
                    createdAt: Date(timeIntervalSince1970: 1_100),
                    lastAccessedAt: Date(timeIntervalSince1970: 2_100),
                    briefing: PersistedBriefingSnapshot(
                        document: BriefingDocument(query: "SQLite briefing"),
                        phase: .complete,
                        conversationHistory: [message]
                    )
                )
            ],
            activeTabID: webTabID,
            isTabBarVisible: true,
            tabBarWidth: 220,
            chatPaneWidth: 380,
            chatPaneHeight: 480,
            chatPaneOffsetX: 0,
            chatPaneOffsetY: 0,
            pageChats: [
                PersistedPageChatSnapshot(
                    pageURL: currentURL,
                    pageTitle: "Current",
                    conversationHistory: [message],
                    updatedAt: Date(timeIntervalSince1970: 2_200),
                    isSidebarVisible: true
                )
            ]
        )
        store.save(state, forWindowID: windowID)

        let restoredViewModel = BrowserViewModel(windowID: windowID, persistenceStore: store)

        #expect(restoredViewModel.tabs.count == 2)
        #expect(restoredViewModel.activeTabID == webTabID)
        let restoredWebTab = try #require(restoredViewModel.tabs.first { $0.id == webTabID })
        let restoredWebVM = try #require(restoredWebTab.webTabViewModel)
        #expect(restoredWebVM.navigationHistorySnapshot == [previousURL, currentURL])
        #expect(restoredWebVM.navigationHistorySnapshotIndex == 1)
        #expect(restoredWebVM.pageZoom == 1.25)
        let restoredBriefingTab = try #require(restoredViewModel.tabs.first { $0.id == briefingTabID })
        #expect(restoredBriefingTab.briefingViewModel?.conversationHistory.first?.content == "What changed?")
        restoredWebVM.currentURL = currentURL
        restoredWebVM.pageTitle = "Current"
        restoredViewModel.toggleChatPane()
        #expect(restoredViewModel.chatViewModel?.conversationHistory.first?.content == "What changed?")
    }

    @Test("Switching workspaces swaps visible tabs and restores active tab")
    func switchingWorkspacesSwapsVisibleTabsAndRestoresActiveTab() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let viewModel = BrowserViewModel(
            restoresPersistedState: false,
            persistenceStore: store
        )
        let defaultWorkspaceID = viewModel.activeWorkspaceID
        let defaultTab = try #require(viewModel.activeTab)
        defaultTab.title = "Default Workspace"
        defaultTab.url = URL(string: "https://example.com/default")

        viewModel.createWorkspace(named: "Research")
        let researchWorkspaceID = viewModel.activeWorkspaceID
        let researchTab = try #require(viewModel.activeTab)
        researchTab.title = "Research Workspace"
        researchTab.url = URL(string: "https://example.com/research")

        viewModel.switchWorkspace(to: defaultWorkspaceID)
        #expect(viewModel.activeWorkspaceID == defaultWorkspaceID)
        #expect(viewModel.tabs.first?.title == "Default Workspace")

        viewModel.switchWorkspace(to: researchWorkspaceID)
        #expect(viewModel.activeWorkspaceID == researchWorkspaceID)
        // Tab IDs are regenerated when a workspace snapshot is applied (they
        // are primary keys shared across windows), so the restored active tab
        // is matched by content rather than identity.
        let restoredActiveTab = try #require(viewModel.activeTab)
        #expect(restoredActiveTab.url == URL(string: "https://example.com/research"))
        #expect(viewModel.tabs.first?.title == "Research Workspace")
    }

    @Test("Switching workspaces preserves the current sidebar width")
    func switchingWorkspacesPreservesCurrentSidebarWidth() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let viewModel = BrowserViewModel(
            restoresPersistedState: false,
            persistenceStore: BrowserPersistenceStore(directoryURL: directory)
        )
        let defaultWorkspaceID = viewModel.activeWorkspaceID
        viewModel.setTabBarWidth(300)

        viewModel.createWorkspace(named: "Research")
        let researchWorkspaceID = viewModel.activeWorkspaceID
        #expect(viewModel.tabBarWidth == 300)

        viewModel.setTabBarWidth(260)
        viewModel.switchWorkspace(to: defaultWorkspaceID)
        #expect(viewModel.tabBarWidth == 260)

        viewModel.switchWorkspace(to: researchWorkspaceID)
        #expect(viewModel.tabBarWidth == 260)
    }

    @Test("Deleting active workspace switches back to default")
    func deletingActiveWorkspaceSwitchesBackToDefault() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let viewModel = BrowserViewModel(
            restoresPersistedState: false,
            persistenceStore: BrowserPersistenceStore(directoryURL: directory)
        )
        let defaultWorkspaceID = viewModel.activeWorkspaceID

        viewModel.createWorkspace(named: "Delete Me")
        let deletedWorkspaceID = viewModel.activeWorkspaceID
        viewModel.deleteWorkspace(deletedWorkspaceID)

        #expect(viewModel.activeWorkspaceID == defaultWorkspaceID)
        #expect(!viewModel.workspaces.contains { $0.id == deletedWorkspaceID })
    }

    @Test("Deleting active workspace with restorable tab does not resurrect it")
    func deletingActiveWorkspaceWithRestorableTabDoesNotResurrectIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let viewModel = BrowserViewModel(
            restoresPersistedState: false,
            persistenceStore: store
        )
        let defaultWorkspaceID = viewModel.activeWorkspaceID

        viewModel.createWorkspace(named: "Delete Me")
        let deletedWorkspaceID = viewModel.activeWorkspaceID
        let tab = try #require(viewModel.activeTab)
        tab.title = "Real Page"
        tab.url = URL(string: "https://example.com/delete-me")

        viewModel.deleteWorkspace(deletedWorkspaceID)

        let persistedWorkspaces = store.loadWorkspaces()
        #expect(viewModel.activeWorkspaceID == defaultWorkspaceID)
        #expect(persistedWorkspaces.map(\.id) == [defaultWorkspaceID])
        #expect(!persistedWorkspaces.contains { $0.id == deletedWorkspaceID })
        #expect(store.loadWorkspaceState(forWorkspaceID: deletedWorkspaceID) == nil)
    }

    @Test("Blank window sharing a workspace does not erase its snapshot")
    func blankWindowSharingWorkspaceDoesNotEraseSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let owner = BrowserViewModel(
            restoresPersistedState: false,
            persistenceStore: store
        )
        let defaultWorkspaceID = owner.activeWorkspaceID

        owner.createWorkspace(named: "Research")
        let workspaceID = owner.activeWorkspaceID
        let ownerTab = try #require(owner.activeTab)
        ownerTab.title = "Paper"
        ownerTab.url = URL(string: "https://example.com/paper")
        owner.switchWorkspace(to: defaultWorkspaceID)
        owner.switchWorkspace(to: workspaceID)
        #expect(store.loadWorkspaceState(forWorkspaceID: workspaceID) != nil)

        // A fresh window adopts the last-opened workspace with a blank tab.
        // Its blank state must not delete the workspace's saved tabs — not on
        // routine persists, and not when it switches away.
        let blankWindow = BrowserViewModel(
            restoresPersistedState: false,
            persistenceStore: store
        )
        #expect(blankWindow.activeWorkspaceID == workspaceID)
        blankWindow.newTab()
        #expect(store.loadWorkspaceState(forWorkspaceID: workspaceID) != nil)
        blankWindow.switchWorkspace(to: defaultWorkspaceID)
        #expect(store.loadWorkspaceState(forWorkspaceID: workspaceID) != nil)
    }

    @Test("Second window opening a workspace persists with regenerated tab IDs")
    func secondWindowOpeningWorkspacePersistsWithRegeneratedTabIDs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let first = BrowserViewModel(
            restoresPersistedState: false,
            persistenceStore: store
        )
        let defaultWorkspaceID = first.activeWorkspaceID

        first.createWorkspace(named: "Shared")
        let workspaceID = first.activeWorkspaceID
        let firstTab = try #require(first.activeTab)
        firstTab.title = "Doc"
        firstTab.url = URL(string: "https://example.com/shared")
        first.switchWorkspace(to: defaultWorkspaceID)
        first.switchWorkspace(to: workspaceID)
        let firstLiveTabID = try #require(first.activeTab?.id)

        // The first window still holds the workspace's tab rows. A second
        // window opening the same workspace must persist under fresh tab IDs;
        // reusing them would violate the tabs primary key and roll back the
        // second window's entire persist transaction.
        let second = BrowserViewModel(
            restoresPersistedState: false,
            persistenceStore: store
        )
        second.switchWorkspace(to: defaultWorkspaceID)
        second.switchWorkspace(to: workspaceID)

        let secondTabID = try #require(second.activeTab?.id)
        #expect(secondTabID != firstLiveTabID)
        let snapshot = try #require(store.loadWorkspaceState(forWorkspaceID: workspaceID))
        #expect(snapshot.tabs.map(\.id) == [secondTabID])
        #expect(snapshot.tabs.first?.url == URL(string: "https://example.com/shared"))
    }

    @Test("Suggested workspace creation names and cycles in workspace order")
    func suggestedWorkspaceCreationNamesAndCyclesInWorkspaceOrder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let viewModel = BrowserViewModel(
            restoresPersistedState: false,
            persistenceStore: BrowserPersistenceStore(directoryURL: directory)
        )

        #expect(viewModel.suggestedWorkspaceName() == "Workspace")
        viewModel.createWorkspaceWithSuggestedName()
        let firstWorkspaceID = viewModel.activeWorkspaceID
        #expect(viewModel.activeWorkspace?.name == "Workspace")
        #expect(viewModel.suggestedWorkspaceName() == "Workspace 2")

        viewModel.createWorkspaceWithSuggestedName()
        #expect(viewModel.activeWorkspace?.name == "Workspace 2")

        var orderedWorkspaceIDs = viewModel.workspaces.map(\.id)
        let currentIndex = try #require(orderedWorkspaceIDs.firstIndex(of: viewModel.activeWorkspaceID))

        viewModel.selectNextWorkspace()
        #expect(viewModel.activeWorkspaceID == orderedWorkspaceIDs[(currentIndex + 1) % orderedWorkspaceIDs.count])

        orderedWorkspaceIDs = viewModel.workspaces.map(\.id)
        let nextIndex = try #require(orderedWorkspaceIDs.firstIndex(of: viewModel.activeWorkspaceID))
        viewModel.selectPreviousWorkspace()
        #expect(viewModel.activeWorkspaceID == orderedWorkspaceIDs[(nextIndex - 1 + orderedWorkspaceIDs.count) % orderedWorkspaceIDs.count])

        orderedWorkspaceIDs = viewModel.workspaces.map(\.id)
        viewModel.switchWorkspace(to: orderedWorkspaceIDs[0])
        orderedWorkspaceIDs = viewModel.workspaces.map(\.id)
        viewModel.selectPreviousWorkspace()
        #expect(viewModel.activeWorkspaceID == orderedWorkspaceIDs.last)
        #expect(viewModel.workspaceSwitchDirection == -1)

        viewModel.selectNextWorkspace()
        #expect(viewModel.workspaceSwitchDirection == 1)
        #expect(viewModel.workspaces.contains { $0.id == firstWorkspaceID })
    }

    @Test("Reopening app restores the last active workspace")
    func reopeningAppRestoresLastActiveWorkspace() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let firstWindow = BrowserViewModel(
            windowID: UUID(),
            restoresPersistedState: false,
            persistenceStore: store
        )

        firstWindow.createWorkspace(named: "Launch Me")
        let workspaceID = firstWindow.activeWorkspaceID
        let tab = try #require(firstWindow.activeTab)
        tab.title = "Launch Workspace"
        tab.url = URL(string: "https://example.com/launch")
        firstWindow.togglePin(tab.id)

        let reopenedWindow = BrowserViewModel(
            windowID: UUID(),
            persistenceStore: store
        )

        #expect(reopenedWindow.activeWorkspaceID == workspaceID)
        #expect(reopenedWindow.activeWorkspace?.name == "Launch Me")
        #expect(reopenedWindow.tabs.first?.title == "Launch Workspace")
    }

    @Test("Private browsing excludes workspace persistence")
    func privateBrowsingExcludesWorkspacePersistence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let windowID = UUID()
        let viewModel = BrowserViewModel(
            windowID: windowID,
            isPrivateBrowsing: true,
            restoresPersistedState: false,
            persistenceStore: store
        )
        let tab = try #require(viewModel.activeTab)
        tab.url = URL(string: "https://example.com/private")

        viewModel.createWorkspace(named: "Private")
        viewModel.switchWorkspace(to: BrowserPersistenceStore.defaultWorkspaceID)

        #expect(viewModel.workspaces.isEmpty)
        #expect(store.loadWindowState(forWindowID: windowID) == nil)
        #expect(store.workspaceID(forWindowID: windowID) == nil)
    }

    @Test("Favorites are shared across workspaces")
    func favoritesAreSharedAcrossWorkspaces() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let viewModel = BrowserViewModel(
            restoresPersistedState: false,
            persistenceStore: store
        )
        let defaultWorkspaceID = viewModel.activeWorkspaceID
        let regular = try #require(viewModel.activeTab)
        regular.title = "Default Page"
        regular.url = URL(string: "https://example.com/default")

        viewModel.newTab()
        let favorite = try #require(viewModel.activeTab)
        favorite.title = "Docs"
        favorite.url = URL(string: "https://example.com/docs")
        viewModel.toggleFavorite(favorite.id)

        viewModel.createWorkspace(named: "Second")
        let secondWorkspaceID = viewModel.activeWorkspaceID

        // The favorite carries over live, with the same identity, and is not
        // part of the new workspace's own tabs.
        #expect(viewModel.tabs.filter(\.isFavorite).map(\.id) == [favorite.id])
        #expect(viewModel.tabs.contains { !$0.isFavorite })

        // Switching back must not duplicate the favorite.
        viewModel.switchWorkspace(to: defaultWorkspaceID)
        #expect(viewModel.tabs.filter(\.isFavorite).map(\.id) == [favorite.id])
        #expect(viewModel.tabs.contains { $0.url == URL(string: "https://example.com/default") })

        // Unfavoriting removes it from every workspace and the global store.
        viewModel.toggleFavorite(favorite.id)
        viewModel.switchWorkspace(to: secondWorkspaceID)
        #expect(viewModel.tabs.filter(\.isFavorite).isEmpty)
        #expect(store.loadGlobalFavorites().isEmpty)
    }

    @Test("Global favorites are restored for new browser instances")
    func globalFavoritesRestoredForNewInstances() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let first = BrowserViewModel(
            restoresPersistedState: false,
            persistenceStore: store
        )
        let favorite = try #require(first.activeTab)
        favorite.title = "Docs"
        favorite.url = URL(string: "https://example.com/docs")
        first.toggleFavorite(favorite.id)

        let second = BrowserViewModel(windowID: UUID(), persistenceStore: store)
        let restoredFavorites = second.tabs.filter(\.isFavorite)
        #expect(restoredFavorites.count == 1)
        #expect(restoredFavorites.first?.url == URL(string: "https://example.com/docs"))
        // Each window materializes favorites under a fresh tab identity.
        #expect(restoredFavorites.first?.id != favorite.id)
    }

    @Test("Legacy per-workspace favorites merge into the global set")
    func legacyFavoritesMergeIntoGlobalSet() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = BrowserPersistenceStore(directoryURL: directory)
        let windowID = UUID()
        let favoriteURL = try #require(URL(string: "https://example.com/legacy-favorite"))
        let regularURL = try #require(URL(string: "https://example.com/regular"))
        let regularTabID = UUID()
        let state = PersistedBrowserState(
            tabs: [
                PersistedTabSnapshot(
                    id: UUID(),
                    kind: .web,
                    title: "Legacy Favorite",
                    url: favoriteURL,
                    navigationHistory: [favoriteURL],
                    navigationHistoryIndex: 0,
                    isFavorite: true,
                    isPinned: false,
                    createdAt: Date(timeIntervalSince1970: 1_000),
                    lastAccessedAt: Date(timeIntervalSince1970: 2_000),
                    briefing: nil
                ),
                PersistedTabSnapshot(
                    id: regularTabID,
                    kind: .web,
                    title: "Regular",
                    url: regularURL,
                    navigationHistory: [regularURL],
                    navigationHistoryIndex: 0,
                    isFavorite: false,
                    isPinned: false,
                    createdAt: Date(timeIntervalSince1970: 1_100),
                    lastAccessedAt: Date(timeIntervalSince1970: 2_100),
                    briefing: nil
                )
            ],
            activeTabID: regularTabID,
            isTabBarVisible: true,
            tabBarWidth: 220,
            chatPaneWidth: nil,
            chatPaneHeight: nil,
            chatPaneOffsetX: nil,
            chatPaneOffsetY: nil,
            pageChats: nil
        )
        store.save(state, forWindowID: windowID)

        let viewModel = BrowserViewModel(windowID: windowID, persistenceStore: store)

        let favorites = viewModel.tabs.filter(\.isFavorite)
        #expect(favorites.count == 1)
        #expect(favorites.first?.url == favoriteURL)
        #expect(viewModel.activeTabID == regularTabID)

        // The merged favorite lands in the global store on the next persist.
        viewModel.newTab()
        #expect(store.loadGlobalFavorites().map(\.url) == [favoriteURL])
    }

    @Test("Closing a favorite unloads it instead of removing it")
    func closingFavoriteUnloadsItInsteadOfRemoving() throws {
        let viewModel = makeViewModel()
        let favorite = try #require(viewModel.activeTab)
        let url = try #require(URL(string: "https://example.com/favorite"))
        favorite.url = url
        favorite.webTabViewModel?.currentURL = url
        viewModel.toggleFavorite(favorite.id)

        viewModel.newTab()
        let other = try #require(viewModel.activeTab)

        viewModel.selectTab(favorite.id)
        viewModel.closeTab(favorite.id)

        #expect(viewModel.tabs.contains { $0.id == favorite.id })
        #expect(favorite.webTabViewModel == nil)
        #expect(favorite.url == url)
        #expect(favorite.isUnloaded)
        #expect(viewModel.activeTabID == other.id)

        // Clicking the unloaded favorite reloads it fresh.
        viewModel.selectTab(favorite.id)
        #expect(viewModel.activeTabID == favorite.id)
        #expect(favorite.webTabViewModel != nil)
    }

    @Test("Closing the only tab when it is a favorite clears the active tab")
    func closingOnlyFavoriteClearsActiveTab() throws {
        let viewModel = makeViewModel()
        let favorite = try #require(viewModel.activeTab)
        favorite.url = URL(string: "https://example.com/only")
        viewModel.toggleFavorite(favorite.id)

        viewModel.closeTab(favorite.id)

        #expect(viewModel.tabs.contains { $0.id == favorite.id })
        #expect(viewModel.activeTabID == nil)
    }

    @Test("Close Others keeps favorites in place but unloads them")
    func closeOthersKeepsFavoritesButUnloadsThem() throws {
        let viewModel = makeViewModel()
        let favorite = try #require(viewModel.activeTab)
        favorite.url = URL(string: "https://example.com/favorite")
        viewModel.toggleFavorite(favorite.id)

        viewModel.newTab()
        viewModel.newTab()
        let kept = try #require(viewModel.activeTab)

        viewModel.closeOtherTabs(keeping: kept.id)

        #expect(viewModel.tabs.count == 2)
        #expect(viewModel.tabs.contains { $0.id == favorite.id })
        #expect(favorite.webTabViewModel == nil)
        #expect(viewModel.activeTabID == kept.id)
    }

    @Test("Cmd-click selection toggles tabs and bulk close applies to selection")
    func multiSelectionTogglesAndBulkCloses() throws {
        let viewModel = makeViewModel()
        let first = try #require(viewModel.activeTab)
        viewModel.newTab()
        let second = try #require(viewModel.activeTab)
        viewModel.newTab()
        let third = try #require(viewModel.activeTab)

        viewModel.selectTab(first.id)
        viewModel.toggleTabSelection(second.id)
        #expect(viewModel.selectedTabIDs == [first.id, second.id])

        viewModel.toggleTabSelection(second.id)
        #expect(viewModel.selectedTabIDs == [first.id])

        viewModel.toggleTabSelection(second.id)
        viewModel.closeSidebarSelection()

        #expect(viewModel.tabs.map(\.id) == [third.id])
        #expect(viewModel.selectedTabIDs.isEmpty)
        #expect(viewModel.activeTabID == third.id)
    }

    @Test("Shift-click extends the selection across the visible range")
    func shiftClickExtendsSelectionRange() throws {
        let viewModel = makeViewModel()
        let first = try #require(viewModel.activeTab)
        viewModel.newTab()
        let second = try #require(viewModel.activeTab)
        viewModel.newTab()
        let third = try #require(viewModel.activeTab)

        viewModel.selectTab(first.id)
        viewModel.extendTabSelection(to: third.id)
        #expect(viewModel.selectedTabIDs == [first.id, second.id, third.id])

        // A plain click clears the multi-selection.
        viewModel.selectTab(second.id)
        #expect(viewModel.selectedTabIDs.isEmpty)
    }

    @Test("Bulk close deletes selected folders together with their tabs")
    func bulkCloseDeletesSelectedFoldersWithTheirTabs() throws {
        let viewModel = makeViewModel()
        let grouped = try #require(viewModel.activeTab)
        let groupID = viewModel.createTabGroup(title: "Work", containing: grouped.id)
        viewModel.newTab()
        let kept = try #require(viewModel.activeTab)

        viewModel.toggleGroupSelection(groupID)
        viewModel.closeSidebarSelection()

        #expect(viewModel.tabGroups.isEmpty)
        #expect(viewModel.tabs.map(\.id) == [kept.id])
        #expect(viewModel.selectedGroupIDs.isEmpty)
    }

    @Test("Shift-click selects a range of folders for a bulk action")
    func shiftClickSelectsFolderRange() {
        let viewModel = makeViewModel()
        let firstGroupID = viewModel.createTabGroup(title: "First")
        let secondGroupID = viewModel.createTabGroup(title: "Second")
        let thirdGroupID = viewModel.createTabGroup(title: "Third")

        viewModel.toggleGroupSelection(firstGroupID)
        viewModel.extendGroupSelection(to: thirdGroupID)

        #expect(viewModel.selectedGroupIDs == [firstGroupID, secondGroupID, thirdGroupID])

        viewModel.closeSidebarSelection()

        #expect(viewModel.tabGroups.isEmpty)
        #expect(viewModel.selectedGroupIDs.isEmpty)
    }

    @Test("Folder actions apply to every selected folder")
    func folderActionsApplyToEverySelectedFolder() throws {
        let viewModel = makeViewModel()
        let firstTab = try #require(viewModel.activeTab)
        let firstGroupID = viewModel.createTabGroup(title: "First", containing: firstTab.id)
        viewModel.newTab()
        let secondTab = try #require(viewModel.activeTab)
        let secondGroupID = viewModel.createTabGroup(title: "Second", containing: secondTab.id)
        let selectedGroupIDs: Set<UUID> = [firstGroupID, secondGroupID]

        viewModel.renameTabGroups(selectedGroupIDs, title: "Selected")
        #expect(viewModel.tabGroups.map(\.title) == ["Selected", "Selected"])

        viewModel.ungroupTabs(in: selectedGroupIDs)
        #expect(viewModel.tabs.allSatisfy { $0.groupID == nil })

        viewModel.toggleGroupSelection(firstGroupID)
        viewModel.toggleGroupSelection(secondGroupID)
        viewModel.deleteTabGroups(selectedGroupIDs)

        #expect(viewModel.tabGroups.isEmpty)
        #expect(viewModel.selectedGroupIDs.isEmpty)
        #expect(viewModel.tabs.map(\.id) == [firstTab.id, secondTab.id])
    }

    private func makeViewModel() -> BrowserViewModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return BrowserViewModel(
            restoresPersistedState: false,
            persistenceStore: BrowserPersistenceStore(directoryURL: directory)
        )
    }
}
