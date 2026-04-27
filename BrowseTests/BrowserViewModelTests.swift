import Foundation
import Testing
@testable import Browse

@MainActor
@Suite("BrowserViewModel")
struct BrowserViewModelTests {
    @Test("Command number selection follows visible tab sections")
    func commandNumberSelectionFollowsVisibleTabSections() {
        let viewModel = BrowserViewModel(restoresPersistedState: false)
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
        let viewModel = BrowserViewModel(restoresPersistedState: false)
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
        let viewModel = BrowserViewModel(restoresPersistedState: false)
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
        let viewModel = BrowserViewModel(restoresPersistedState: false)
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
        let viewModel = BrowserViewModel(restoresPersistedState: false)
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
        let viewModel = BrowserViewModel(restoresPersistedState: false)
        let tab = try #require(viewModel.activeTab)
        let webVM = try #require(tab.webTabViewModel)

        tab.url = URL(string: "https://example.com/stored")
        #expect(viewModel.activeTabURL == tab.url)

        webVM.currentURL = URL(string: "https://example.com/live")
        #expect(viewModel.activeTabURL == webVM.currentURL)
    }

    @Test("Copy URL indicator becomes visible")
    func copyURLIndicatorBecomesVisible() {
        let viewModel = BrowserViewModel(restoresPersistedState: false)

        #expect(!viewModel.isCurrentURLCopyIndicatorVisible)
        viewModel.showCurrentURLCopiedIndicator()
        #expect(viewModel.isCurrentURLCopyIndicatorVisible)
    }

    @Test("Page chat sidebar visibility follows the active page")
    func pageChatSidebarVisibilityFollowsActivePage() throws {
        let viewModel = BrowserViewModel(restoresPersistedState: false)
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
}
