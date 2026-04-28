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
        let restoredBriefingTab = try #require(restoredViewModel.tabs.first { $0.id == briefingTabID })
        #expect(restoredBriefingTab.briefingViewModel?.conversationHistory.first?.content == "What changed?")
        restoredWebVM.currentURL = currentURL
        restoredWebVM.pageTitle = "Current"
        restoredViewModel.toggleChatPane()
        #expect(restoredViewModel.chatViewModel?.conversationHistory.first?.content == "What changed?")
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
