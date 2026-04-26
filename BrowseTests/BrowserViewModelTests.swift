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
}
