import Foundation
import Testing
import WebKit
@testable import Browse

@MainActor
@Suite("WebTabViewModel find in page")
struct WebTabViewModelTests {
    @Test("WebKit native context-menu downloads are routed to DownloadManager")
    func nativeContextMenuDownloadsAreRoutedToDownloadManager() {
        let viewModel = WebTabViewModel(websiteDataStore: .nonPersistent())
        defer { viewModel.closePage() }

        #expect(
            viewModel.responds(
                to: NSSelectorFromString("_webView:contextMenuDidCreateDownload:")
            )
        )
    }

    @Test("A context-menu WKDownload selects a destination and completes on disk")
    func nativeContextMenuDownloadCompletesOnDisk() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let downloadManager = DownloadManager(
            downloadsDirectoryURL: directory,
            historyStore: DownloadHistoryStore(
                fileURL: directory.appendingPathComponent("history.json")
            ),
            loadsSavedDownloads: false
        )
        let viewModel = WebTabViewModel(
            websiteDataStore: .nonPersistent(),
            downloadManager: downloadManager
        )
        defer { viewModel.closePage() }

        let expectedData = try #require("context menu image".data(using: .utf8))
        let sourceURL = try #require(
            URL(string: "data:application/octet-stream;base64,\(expectedData.base64EncodedString())")
        )
        let download = await viewModel.webView.startDownload(
            using: URLRequest(url: sourceURL)
        )

        _ = viewModel.perform(
            NSSelectorFromString("_webView:contextMenuDidCreateDownload:"),
            with: viewModel.webView,
            with: download
        )

        #expect(download.delegate === downloadManager)

        let response = URLResponse(
            url: sourceURL,
            mimeType: "application/octet-stream",
            expectedContentLength: expectedData.count,
            textEncodingName: nil
        )
        var selectedDestination: URL?
        downloadManager.download(
            download,
            decideDestinationUsing: response,
            suggestedFilename: "image.bin"
        ) { destinationURL in
            selectedDestination = destinationURL
        }

        let destinationURL = try #require(selectedDestination)
        try expectedData.write(to: destinationURL)
        downloadManager.downloadDidFinish(download)
        download.delegate = nil
        _ = await download.cancel()

        let item = try #require(downloadManager.downloads.first)
        #expect(item.state == .completed)
        #expect(item.destinationURL == destinationURL)
        #expect(FileManager.default.fileExists(atPath: destinationURL.path))
        #expect(try Data(contentsOf: destinationURL) == expectedData)
    }

    @Test("Attachment responses download even when WebKit can display them")
    func attachmentResponsesDownloadWhenDisplayable() {
        let policy = WebTabViewModel.navigationResponsePolicy(
            canShowMIMEType: true,
            contentDisposition: " Attachment ; filename=report.pdf"
        )

        #expect(policy == .download)
    }

    @Test("Inline responses use WebKit MIME support to choose their policy")
    func inlineResponsesFollowMIMESupport() {
        #expect(
            WebTabViewModel.navigationResponsePolicy(
                canShowMIMEType: true,
                contentDisposition: "inline; filename=report.pdf"
            ) == .allow
        )
        #expect(
            WebTabViewModel.navigationResponsePolicy(
                canShowMIMEType: false,
                contentDisposition: nil
            ) == .download
        )
    }

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
