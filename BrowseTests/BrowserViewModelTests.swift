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
