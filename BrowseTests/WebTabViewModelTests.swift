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

    @Test("Page zoom clamps, resets, and reports state")
    func pageZoomClampsResetsAndReportsState() {
        let viewModel = WebTabViewModel(websiteDataStore: .nonPersistent())
        var stateChangeCount = 0
        viewModel.onStateChange = {
            stateChangeCount += 1
        }

        #expect(viewModel.pageZoom == WebTabViewModel.defaultPageZoom)
        #expect(viewModel.pageZoomDisplayText == "100%")
        #expect(!viewModel.canResetZoom)

        viewModel.setPageZoom(99)
        #expect(viewModel.pageZoom == WebTabViewModel.maximumPageZoom)
        #expect(viewModel.pageZoomDisplayText == "300%")
        #expect(!viewModel.canZoomIn)
        #expect(viewModel.canZoomOut)

        viewModel.setPageZoom(-1)
        #expect(viewModel.pageZoom == WebTabViewModel.minimumPageZoom)
        #expect(viewModel.pageZoomDisplayText == "50%")
        #expect(viewModel.canZoomIn)
        #expect(!viewModel.canZoomOut)

        viewModel.resetZoom()
        #expect(viewModel.pageZoom == WebTabViewModel.defaultPageZoom)
        #expect(viewModel.pageZoomDisplayText == "100%")
        #expect(!viewModel.canResetZoom)
        #expect(stateChangeCount == 3)
    }

    @Test("Site permission entries follow the current page and reset")
    func sitePermissionEntriesFollowCurrentPageAndReset() throws {
        let store = SitePermissionStore(persistsDecisions: false)
        let url = try #require(URL(string: "https://example.com/camera"))
        let origin = try #require(SitePermissionOrigin(url: url))
        store.setDecision(.allow, for: [.camera], origin: origin)

        let viewModel = WebTabViewModel(
            websiteDataStore: .nonPersistent(),
            sitePermissionStore: store
        )
        viewModel.currentURL = url

        #expect(viewModel.currentSitePermissionEntries == [
            SitePermissionEntry(kind: .camera, decision: .allow)
        ])

        viewModel.resetPermissionDecisionsForCurrentSite()
        #expect(viewModel.currentSitePermissionEntries.isEmpty)
        #expect(store.decision(for: .camera, origin: origin) == nil)
    }
}
