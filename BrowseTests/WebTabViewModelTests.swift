import Foundation
import Testing
import WebKit
@testable import Browse

@MainActor
@Suite("WebTabViewModel find in page")
struct WebTabViewModelTests {
    @Test("Find bar opens only when a page is loaded")
    func findBarOpensOnlyWhenPageIsLoaded() throws {
        let viewModel = WebTabViewModel(websiteDataStore: .nonPersistent())

        viewModel.showFindBar()
        #expect(!viewModel.isFindBarVisible)
        #expect(viewModel.findBarFocusRequestID == 0)

        viewModel.currentURL = try #require(URL(string: "https://example.com"))
        viewModel.showFindBar()

        #expect(viewModel.isFindBarVisible)
        #expect(viewModel.findBarFocusRequestID == 1)

        viewModel.closeFindBar()
        #expect(!viewModel.isFindBarVisible)
    }

    @Test("Find status describes empty, pending, missing, and selected matches")
    func findStatusTextReflectsMatchState() {
        let viewModel = WebTabViewModel(websiteDataStore: .nonPersistent())

        #expect(viewModel.findStatusText == "")

        viewModel.findQuery = "needle"
        #expect(viewModel.findStatusText == "Searching...")

        viewModel.findMatchCount = 0
        #expect(viewModel.findStatusText == "No results")

        viewModel.findMatchCount = 5
        viewModel.findCurrentMatchIndex = 2
        #expect(viewModel.findStatusText == "2 of 5")
    }
}
