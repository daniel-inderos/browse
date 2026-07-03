import SwiftUI
import WebKit
import AppKit
import OSLog

private let webTabLogger = Logger(subsystem: "com.browse.app", category: "WebTab")

// MARK: - Scroll message bridge

/// Lightweight message handler that forwards WKWebView scroll‐position
/// messages back to the owning view model without creating a retain cycle.
private final class ScrollMessageHandler: NSObject, WKScriptMessageHandler {
    var onScroll: (@Sendable (CGFloat) -> Void)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? NSNumber else { return }
        onScroll?(CGFloat(body.doubleValue))
    }
}

private final class ContextLinkMessageHandler: NSObject, WKScriptMessageHandler {
    var onContextLinkChange: (@Sendable (URL?) -> Void)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let href = message.body as? String,
              let url = URL(string: href) else {
            onContextLinkChange?(nil)
            return
        }

        onContextLinkChange?(url)
    }
}

private final class NewTabLinkMessageHandler: NSObject, WKScriptMessageHandler {
    var onOpenLinkInNewTab: (@Sendable (URL) -> Void)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let href = message.body as? String,
              let url = URL(string: href) else { return }

        onOpenLinkInNewTab?(url)
    }
}

private final class BrowserWebView: WKWebView {
    var contextMenuLinkURL: URL?
    var onOpenContextLinkInNewTab: ((URL) -> Void)?
    var onDownloadContextLink: ((URL) -> Void)?
    private var isObservingLinkMenus = false

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func observeLinkMenus() {
        guard !isObservingLinkMenus else { return }
        isObservingLinkMenus = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidBeginTracking(_:)),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
    }

    @objc private func menuDidBeginTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        addOpenLinkInNewTabItemIfNeeded(to: menu)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        guard let contextMenuLinkURL else { return menu }

        let resolvedMenu = menu ?? NSMenu()
        addOpenLinkInNewTabItemIfNeeded(to: resolvedMenu, url: contextMenuLinkURL)

        return resolvedMenu
    }

    private func addOpenLinkInNewTabItemIfNeeded(to menu: NSMenu, url: URL? = nil) {
        guard let url = url ?? contextMenuLinkURL else { return }
        guard isLinkMenu(menu) else { return }

        if let existingItem = menu.items.first(where: { $0.title == "Open Link in New Tab" }) {
            existingItem.target = self
            existingItem.action = #selector(openContextLinkInNewTab(_:))
            existingItem.representedObject = url
            addDownloadLinkedFileItemIfNeeded(to: menu, url: url)
            return
        }

        let item = NSMenuItem(
            title: "Open Link in New Tab",
            action: #selector(openContextLinkInNewTab(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = url

        if let windowIndex = menu.items.firstIndex(where: { $0.title == "Open Link in New Window" }) {
            menu.insertItem(item, at: windowIndex)
        } else if menu.items.isEmpty {
            menu.addItem(item)
        } else {
            menu.insertItem(item, at: 0)
        }

        addDownloadLinkedFileItemIfNeeded(to: menu, url: url)
    }

    private func addDownloadLinkedFileItemIfNeeded(to menu: NSMenu, url: URL) {
        if let existingItem = menu.items.first(where: { $0.title == "Download Linked File" }) {
            existingItem.target = self
            existingItem.action = #selector(downloadContextLink(_:))
            existingItem.representedObject = url
            return
        }

        let item = NSMenuItem(
            title: "Download Linked File",
            action: #selector(downloadContextLink(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = url

        if let openLinkIndex = menu.items.firstIndex(where: { $0.title == "Open Link in New Tab" }) {
            menu.insertItem(item, at: openLinkIndex + 1)
        } else {
            menu.addItem(item)
        }
    }

    private func isLinkMenu(_ menu: NSMenu) -> Bool {
        let titles = Set(menu.items.map(\.title))
        return titles.contains("Copy Link") ||
            titles.contains("Open Link") ||
            titles.contains("Open Link in New Window") ||
            titles.contains("Download Linked File")
    }

    @objc private func openContextLinkInNewTab(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onOpenContextLinkInNewTab?(url)
    }

    @objc private func downloadContextLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onDownloadContextLink?(url)
    }
}

// MARK: - WebTabViewModel

@MainActor
@Observable
final class WebTabViewModel: NSObject {
    var currentURL: URL? {
        didSet {
            guard currentURL != oldValue else { return }
            refreshCurrentSitePermissionEntries()
        }
    }
    var pageTitle: String = "New Tab"
    var isLoading: Bool = false
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var estimatedProgress: Double = 0
    var faviconURL: URL?
    var onStateChange: (() -> Void)?
    var onScrollPositionChange: ((CGFloat) -> Void)?
    var onOpenURLInNewTab: ((URL, Bool) -> Void)?
    var navigationHistorySnapshot: [URL] { navigationHistory }
    var navigationHistorySnapshotIndex: Int? { navigationHistoryIndex }
    var isFindBarVisible: Bool = false
    var findQuery: String = ""
    var findMatchCount: Int?
    var findCurrentMatchIndex: Int?
    var findBarFocusRequestID: Int = 0
    private(set) var currentSitePermissionEntries: [SitePermissionEntry] = []
    var currentSitePermissionOrigin: SitePermissionOrigin? {
        SitePermissionOrigin(url: currentURL)
    }
    var currentSitePermissionHost: String? {
        currentSitePermissionOrigin?.displayName
    }
    var canFindInPage: Bool { currentURL != nil }
    private(set) var pageZoom: Double = WebTabViewModel.defaultPageZoom
    var pageZoomPercent: Int { Int((pageZoom * 100).rounded()) }
    var pageZoomDisplayText: String { "\(pageZoomPercent)%" }
    var canZoomIn: Bool { pageZoom < Self.maximumPageZoom }
    var canZoomOut: Bool { pageZoom > Self.minimumPageZoom }
    var canResetZoom: Bool { pageZoom != Self.defaultPageZoom }
    var findStatusText: String {
        guard !findQuery.isEmpty else { return "" }
        guard let findMatchCount else { return "Searching..." }
        guard findMatchCount > 0 else { return "No results" }
        return "\(findCurrentMatchIndex ?? 1) of \(findMatchCount)"
    }

    private(set) var webView: WKWebView
    private let downloadManager: DownloadManager
    private let isPrivateBrowsing: Bool
    private let workspaceIDProvider: @MainActor () -> UUID?
    private let sitePermissionStore: SitePermissionStore
    private var observations: [NSKeyValueObservation] = []
    private(set) var scrollOffsetY: CGFloat = 0
    private var navigationHistory: [URL] = []
    private var navigationHistoryIndex: Int?
    private var pendingHistoryLoadIndex: Int?
    private var usesRestoredNavigationHistoryFallback = false
    @ObservationIgnored private var findOperationID = 0

    /// Prevent the handler from being collected while the content controller retains it.
    private var scrollHandler: ScrollMessageHandler?
    private var contextLinkHandler: ContextLinkMessageHandler?
    private var newTabLinkHandler: NewTabLinkMessageHandler?

    static let defaultPageZoom = 1.0
    static let minimumPageZoom = 0.5
    static let maximumPageZoom = 3.0
    static let pageZoomStep = 0.1

    init(
        websiteDataStore: WKWebsiteDataStore = .default(),
        downloadManager: DownloadManager = .shared,
        isPrivateBrowsing: Bool = false,
        workspaceIDProvider: @escaping @MainActor () -> UUID? = { nil },
        sitePermissionStore: SitePermissionStore = .shared
    ) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = websiteDataStore
        config.preferences.isElementFullscreenEnabled = true
        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = true
        pagePreferences.preferredContentMode = .desktop
        config.defaultWebpagePreferences = pagePreferences

        // ── JavaScript scroll observer ──────────────────────────
        // Inject a passive scroll listener that posts the current
        // pageYOffset back via the webkit message bridge.
        let scrollScript = WKUserScript(
            source: Self.scrollObserverJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(scrollScript)
        let contextLinkScript = WKUserScript(
            source: Self.contextLinkObserverJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(contextLinkScript)
        let newTabLinkScript = WKUserScript(
            source: Self.newTabLinkObserverJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(newTabLinkScript)

        self.webView = BrowserWebView(frame: .zero, configuration: config)
        self.downloadManager = downloadManager
        self.isPrivateBrowsing = isPrivateBrowsing
        self.workspaceIDProvider = workspaceIDProvider
        self.sitePermissionStore = sitePermissionStore
        super.init()

        // Wire up the message handler *after* super.init so we can
        // reference `self` (weakly) in the callback.
        let handler = ScrollMessageHandler()
        handler.onScroll = { [weak self] offsetY in
            Task { @MainActor [weak self] in
                self?.handleScrollMessage(offsetY)
            }
        }
        self.scrollHandler = handler
        webView.configuration.userContentController.add(handler, name: "scrollObserver")

        let contextLinkHandler = ContextLinkMessageHandler()
        contextLinkHandler.onContextLinkChange = { [weak self] url in
            Task { @MainActor [weak self] in
                (self?.webView as? BrowserWebView)?.contextMenuLinkURL = url
            }
        }
        self.contextLinkHandler = contextLinkHandler
        webView.configuration.userContentController.add(contextLinkHandler, name: "contextLinkObserver")
        (webView as? BrowserWebView)?.onOpenContextLinkInNewTab = { [weak self] url in
            self?.openInNewTab(url, activates: false)
        }
        (webView as? BrowserWebView)?.onDownloadContextLink = { [weak self] url in
            Task { @MainActor [weak self] in
                self?.downloadLinkedFile(url)
            }
        }
        (webView as? BrowserWebView)?.observeLinkMenus()

        let newTabLinkHandler = NewTabLinkMessageHandler()
        newTabLinkHandler.onOpenLinkInNewTab = { [weak self] url in
            Task { @MainActor [weak self] in
                self?.openInNewTab(url, activates: false)
            }
        }
        self.newTabLinkHandler = newTabLinkHandler
        webView.configuration.userContentController.add(newTabLinkHandler, name: "newTabLinkObserver")

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = Self.desktopSafariUserAgent
        applyPageZoom()
        setUpWebViewObservers()
    }

    /// Google serves reduced layouts to some embedded webviews.
    /// A desktop Safari UA helps keep desktop rendering consistent.
    private static let desktopSafariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// JavaScript injected at document-end on every page load.
    /// Tracks both window-level scroll and nested scroll containers.
    /// requestAnimationFrame + light polling keeps it responsive.
    private static let scrollObserverJS = """
    (function() {
        var lastY = -1;
        var ticking = false;

        function bestOffset(target) {
            var doc = document.documentElement || document.body;
            var windowY = window.pageYOffset || window.scrollY || 0;
            var docY = doc ? doc.scrollTop : 0;
            var bodyY = document.body ? document.body.scrollTop : 0;
            var targetY = 0;
            if (target && typeof target.scrollTop === 'number') {
                targetY = target.scrollTop;
            } else if (target && target.parentElement && typeof target.parentElement.scrollTop === 'number') {
                targetY = target.parentElement.scrollTop;
            }
            return Math.max(windowY, docY, bodyY, targetY);
        }

        function report(target) {
            if (!ticking) {
                ticking = true;
                requestAnimationFrame(function() {
                    var y = bestOffset(target);
                    if (Math.abs(y - lastY) > 2) {
                        lastY = y;
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.scrollObserver) {
                            window.webkit.messageHandlers.scrollObserver.postMessage(y);
                        }
                    }
                    ticking = false;
                });
            }
        }

        window.addEventListener('scroll', function() { report(window); }, { passive: true });
        document.addEventListener('scroll', function(e) { report(e.target); }, true);
        window.addEventListener('wheel', function(e) { report(e.target); }, { passive: true, capture: true });

        // Fallback for programmatic scroll changes and dynamic app shells.
        setInterval(function() { report(document.scrollingElement || document.documentElement); }, 250);

        report(document.scrollingElement || document.documentElement);
    })();
    """

    private static let contextLinkObserverJS = """
    (function() {
        var lastHref = undefined;

        function linkURL(fromTarget) {
            var node = fromTarget;
            while (node && node !== document) {
                if (node.tagName && node.tagName.toLowerCase() === 'a' && node.href) {
                    return node.href;
                }
                node = node.parentNode;
            }
            return null;
        }

        function report(href) {
            if (href === lastHref) { return; }
            lastHref = href;
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.contextLinkObserver) {
                window.webkit.messageHandlers.contextLinkObserver.postMessage(href || '');
            }
        }

        document.addEventListener('mousemove', function(event) {
            report(linkURL(event.target));
        }, true);

        document.addEventListener('mousedown', function(event) {
            if (event.button === 2) {
                report(linkURL(event.target));
            }
        }, true);

        document.addEventListener('contextmenu', function(event) {
            report(linkURL(event.target));
        }, true);
    })();
    """

    private static let newTabLinkObserverJS = """
    (function() {
        function linkURL(fromTarget) {
            var node = fromTarget;
            while (node && node !== document) {
                if (node.tagName && node.tagName.toLowerCase() === 'a' && node.href) {
                    return node.href;
                }
                node = node.parentNode;
            }
            return null;
        }

        function openInBackgroundTab(event) {
            var href = linkURL(event.target);
            if (!href) { return; }
            event.preventDefault();
            event.stopPropagation();
            if (event.stopImmediatePropagation) {
                event.stopImmediatePropagation();
            }
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.newTabLinkObserver) {
                window.webkit.messageHandlers.newTabLinkObserver.postMessage(href);
            }
        }

        document.addEventListener('mousedown', function(event) {
            if (event.button === 1 && linkURL(event.target)) {
                event.preventDefault();
            }
        }, true);

        document.addEventListener('auxclick', function(event) {
            if (event.button === 1) {
                openInBackgroundTab(event);
            }
        }, true);
    })();
    """

    private static let stopMediaJS = """
    (function() {
        document.querySelectorAll('audio, video').forEach(function(element) {
            try {
                element.pause();
                element.removeAttribute('src');
                element.load();
            } catch (_) {}
        });
    })();
    """

    /// Extracts the main text content of the current page via JS evaluation.
    /// Returns up to `maxLength` characters of `document.body.innerText`.
    func extractPageContent(maxLength: Int = 12_000) async -> String? {
        guard currentURL != nil else { return nil }
        let js = """
        (function() {
            var text = document.body ? document.body.innerText : '';
            return text.substring(0, \(maxLength));
        })();
        """
        do {
            let result = try await webView.evaluateJavaScript(js)
            return result as? String
        } catch {
            webTabLogger.warning("Page content extraction failed; category=\(Self.errorCategory(error), privacy: .public)")
            return nil
        }
    }

    func navigate(to url: URL) {
        let request = URLRequest(url: url)
        webView.load(request)
    }

    func goBack() {
        if usesRestoredNavigationHistoryFallback {
            loadHistoryEntry(offset: -1)
            return
        }

        if webView.canGoBack {
            webView.goBack()
        } else {
            loadHistoryEntry(offset: -1)
        }
    }

    func goForward() {
        if usesRestoredNavigationHistoryFallback {
            loadHistoryEntry(offset: 1)
            return
        }

        if webView.canGoForward {
            webView.goForward()
        } else {
            loadHistoryEntry(offset: 1)
        }
    }

    func reload() { webView.reload() }
    func reloadFromOrigin() { webView.reloadFromOrigin() }
    func stopLoading() { webView.stopLoading() }

    func zoomIn() {
        setPageZoom(pageZoom + Self.pageZoomStep)
    }

    func zoomOut() {
        setPageZoom(pageZoom - Self.pageZoomStep)
    }

    func resetZoom() {
        setPageZoom(Self.defaultPageZoom)
    }

    func setPageZoom(_ zoom: Double) {
        let clampedZoom = Self.clampedPageZoom(zoom)
        guard clampedZoom != pageZoom else { return }
        pageZoom = clampedZoom
        applyPageZoom()
        onStateChange?()
    }

    func restorePageZoom(_ zoom: Double?) {
        pageZoom = Self.clampedPageZoom(zoom ?? Self.defaultPageZoom)
        applyPageZoom()
    }

    func showFindBar() {
        guard canFindInPage else { return }
        isFindBarVisible = true
        findBarFocusRequestID += 1

        if !findQuery.isEmpty {
            performFind(backwards: false, resetsIndex: findCurrentMatchIndex == nil)
        }
    }

    func closeFindBar() {
        isFindBarVisible = false
        webView.window?.makeFirstResponder(webView)
    }

    func updateFindQuery(_ query: String) {
        guard findQuery != query else { return }
        findQuery = query
        findOperationID += 1

        guard !query.isEmpty else {
            findMatchCount = nil
            findCurrentMatchIndex = nil
            return
        }

        findMatchCount = nil
        findCurrentMatchIndex = nil
        performFind(backwards: false, resetsIndex: true)
    }

    func findNext() {
        performFind(backwards: false, resetsIndex: false)
    }

    func findPrevious() {
        performFind(backwards: true, resetsIndex: false)
    }

    func closePage() {
        onStateChange = nil
        onScrollPositionChange = nil
        onOpenURLInNewTab = nil
        observations.removeAll()

        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        (webView as? BrowserWebView)?.onOpenContextLinkInNewTab = nil
        (webView as? BrowserWebView)?.onDownloadContextLink = nil

        let userContentController = webView.configuration.userContentController
        userContentController.removeScriptMessageHandler(forName: "scrollObserver")
        userContentController.removeScriptMessageHandler(forName: "contextLinkObserver")
        userContentController.removeScriptMessageHandler(forName: "newTabLinkObserver")

        webView.evaluateJavaScript(Self.stopMediaJS, completionHandler: nil)
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)

        currentURL = nil
        pageTitle = "New Tab"
        isLoading = false
        canGoBack = false
        canGoForward = false
        estimatedProgress = 0
        faviconURL = nil
        currentSitePermissionEntries = []
        resetFindState()
    }

    func restoreNavigationHistory(_ urls: [URL], currentIndex: Int?) {
        navigationHistory = urls
        if navigationHistory.isEmpty {
            navigationHistoryIndex = nil
            usesRestoredNavigationHistoryFallback = false
        } else {
            let fallbackIndex = currentIndex ?? navigationHistory.index(before: navigationHistory.endIndex)
            navigationHistoryIndex = max(0, min(fallbackIndex, navigationHistory.index(before: navigationHistory.endIndex)))
            usesRestoredNavigationHistoryFallback = navigationHistory.count > 1
        }
        updateBackForwardAvailability()
    }

    func clearNavigationHistoryKeepingCurrentPage() {
        if let currentURL {
            navigationHistory = [currentURL]
            navigationHistoryIndex = 0
        } else {
            navigationHistory = []
            navigationHistoryIndex = nil
        }
        pendingHistoryLoadIndex = nil
        usesRestoredNavigationHistoryFallback = false
        updateBackForwardAvailability()
        onStateChange?()
    }

    // MARK: - Scroll handling

    private func handleScrollMessage(_ offsetY: CGFloat) {
        guard abs(offsetY - scrollOffsetY) > 0.5 else { return }
        scrollOffsetY = offsetY
        onScrollPositionChange?(offsetY)
    }

    private static func errorCategory(_ error: Error) -> String {
        if let cocoaError = error as? CocoaError {
            return "cocoa-\(cocoaError.errorCode)"
        }
        if let urlError = error as? URLError {
            return "url-\(urlError.errorCode)"
        }
        return "unknown"
    }

    private func openInNewTab(_ url: URL, activates: Bool = true) {
        onOpenURLInNewTab?(url, activates)
    }

    func resetPermissionDecisionsForCurrentSite() {
        guard let origin = currentSitePermissionOrigin else { return }
        sitePermissionStore.resetDecisions(for: origin)
        refreshCurrentSitePermissionEntries()
    }

    private static func clampedPageZoom(_ zoom: Double) -> Double {
        min(maximumPageZoom, max(minimumPageZoom, (zoom * 100).rounded() / 100))
    }

    private func applyPageZoom() {
        webView.pageZoom = CGFloat(pageZoom)
    }

    private func downloadLinkedFile(_ url: URL) {
        webView.startDownload(using: URLRequest(url: url)) { [weak self] download in
            guard let self else { return }
            self.downloadManager.begin(download, sourceURL: url, workspaceID: self.downloadWorkspaceID)
        }
    }

    private var downloadWorkspaceID: UUID? {
        isPrivateBrowsing ? nil : workspaceIDProvider()
    }

    private func refreshCurrentSitePermissionEntries() {
        currentSitePermissionEntries = sitePermissionStore.entries(for: currentSitePermissionOrigin)
    }

    private func mediaCaptureDecision(
        for origin: SitePermissionOrigin,
        kinds: [SitePermissionKind]
    ) -> WKPermissionDecision? {
        let storedDecisions = kinds.map { sitePermissionStore.decision(for: $0, origin: origin) }

        if storedDecisions.contains(.deny) {
            return .deny
        }

        if storedDecisions.allSatisfy({ $0 == .allow }) {
            return .grant
        }

        return nil
    }

    private func shouldAllowScriptedPopup(
        to url: URL,
        requestedBy requestOriginURL: URL?
    ) -> Bool {
        guard let origin = SitePermissionOrigin(url: requestOriginURL ?? currentURL ?? url) else {
            return false
        }

        if let storedDecision = sitePermissionStore.decision(for: .popups, origin: origin) {
            return storedDecision.isAllowed
        }

        let decision = presentSitePermissionPrompt(
            origin: origin,
            kinds: [.popups],
            actionDescription: "open pop-ups"
        )
        return decision.isAllowed
    }

    private func presentSitePermissionPrompt(
        origin: SitePermissionOrigin,
        kinds: [SitePermissionKind],
        actionDescription: String
    ) -> SitePermissionDecision {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "\(origin.displayName) wants to \(actionDescription)."
        alert.informativeText = isPrivateBrowsing
            ? "Allow only if you trust this site. This decision is remembered for this private window only."
            : "Allow only if you trust this site."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Deny")

        let rememberCheckbox: NSButton?
        if isPrivateBrowsing {
            rememberCheckbox = nil
        } else {
            let checkbox = NSButton(checkboxWithTitle: "Remember for this site", target: nil, action: nil)
            checkbox.state = .on
            alert.accessoryView = checkbox
            rememberCheckbox = checkbox
        }

        let response = alert.runModal()
        let decision: SitePermissionDecision = response == .alertFirstButtonReturn ? .allow : .deny
        let shouldStoreDecision = rememberCheckbox?.state == .on || isPrivateBrowsing
        if shouldStoreDecision {
            sitePermissionStore.setDecision(decision, for: kinds, origin: origin)
            refreshCurrentSitePermissionEntries()
        }

        return decision
    }

    // MARK: - Find in page

    private struct FindMatchSnapshot {
        let count: Int
        let selectedIndex: Int?
    }

    private func resetFindState() {
        isFindBarVisible = false
        findQuery = ""
        findMatchCount = nil
        findCurrentMatchIndex = nil
        findOperationID += 1
    }

    private func resetFindResultsForPageChange() {
        findOperationID += 1
        findMatchCount = findQuery.isEmpty ? nil : 0
        findCurrentMatchIndex = nil
    }

    private func performFind(backwards: Bool, resetsIndex: Bool) {
        guard canFindInPage, !findQuery.isEmpty else { return }

        let query = findQuery
        findOperationID += 1
        let operationID = findOperationID
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.wraps = true

        webView.find(query, configuration: configuration) { [weak self] result in
            Task { @MainActor [weak self] in
                await self?.handleFindResult(
                    result,
                    query: query,
                    operationID: operationID,
                    backwards: backwards,
                    resetsIndex: resetsIndex
                )
            }
        }
    }

    private func handleFindResult(
        _ result: WKFindResult,
        query: String,
        operationID: Int,
        backwards: Bool,
        resetsIndex: Bool
    ) async {
        guard operationID == findOperationID, query == findQuery else { return }

        if !result.matchFound {
            let snapshot = await findMatchSnapshot(for: query)
            guard operationID == findOperationID, query == findQuery else { return }
            findMatchCount = snapshot?.count ?? 0
            findCurrentMatchIndex = nil
            return
        }

        let fallbackIndex = trackedFindIndexAfterSuccessfulFind(
            backwards: backwards,
            resetsIndex: resetsIndex
        )
        let snapshot = await findMatchSnapshot(for: query)
        guard operationID == findOperationID, query == findQuery else { return }

        if let snapshot {
            findMatchCount = snapshot.count
            if snapshot.count > 0 {
                findCurrentMatchIndex = snapshot.selectedIndex ?? fallbackIndex
            } else {
                findCurrentMatchIndex = nil
            }
        } else {
            findCurrentMatchIndex = fallbackIndex
        }
    }

    private func trackedFindIndexAfterSuccessfulFind(backwards: Bool, resetsIndex: Bool) -> Int {
        if resetsIndex || findCurrentMatchIndex == nil {
            if backwards, let findMatchCount, findMatchCount > 0 {
                return findMatchCount
            }
            return 1
        }

        let current = findCurrentMatchIndex ?? 1
        guard let findMatchCount, findMatchCount > 0 else {
            return max(1, current + (backwards ? -1 : 1))
        }

        if backwards {
            return current > 1 ? current - 1 : findMatchCount
        }
        return current < findMatchCount ? current + 1 : 1
    }

    private func findMatchSnapshot(for query: String) async -> FindMatchSnapshot? {
        guard let queryLiteral = Self.javaScriptStringLiteral(query) else { return nil }
        let js = Self.findMatchSnapshotJS(queryLiteral: queryLiteral)

        do {
            guard let result = try await webView.evaluateJavaScript(js) as? [String: Any],
                  let countNumber = result["count"] as? NSNumber else {
                return nil
            }
            let selectedIndex = (result["selectedIndex"] as? NSNumber)?.intValue
            return FindMatchSnapshot(count: countNumber.intValue, selectedIndex: selectedIndex)
        } catch {
            webTabLogger.warning("Find match snapshot failed; category=\(Self.errorCategory(error), privacy: .public)")
            return nil
        }
    }

    private static func javaScriptStringLiteral(_ string: String) -> String? {
        guard let data = try? JSONEncoder().encode(string) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func findMatchSnapshotJS(queryLiteral: String) -> String {
        """
        (function(needle) {
            if (!needle || !document.body) {
                return { count: 0, selectedIndex: null };
            }

            var needleLower = needle.toLocaleLowerCase();
            var selection = window.getSelection ? window.getSelection() : null;
            var selectedRange = selection && selection.rangeCount ? selection.getRangeAt(0) : null;
            var selectedText = selection ? selection.toString().toLocaleLowerCase() : '';
            var count = 0;
            var selectedIndex = null;

            function acceptsTextNode(node) {
                if (!node || !node.nodeValue) { return false; }
                var parent = node.parentElement;
                if (!parent) { return false; }
                var tag = parent.tagName ? parent.tagName.toLowerCase() : '';
                if (tag === 'script' || tag === 'style' || tag === 'noscript') { return false; }
                var style = window.getComputedStyle ? window.getComputedStyle(parent) : null;
                if (style && (style.display === 'none' || style.visibility === 'hidden')) { return false; }
                return true;
            }

            function isSelectedMatch(node, start) {
                if (!selectedRange || selectedText !== needleLower) { return false; }
                try {
                    var range = document.createRange();
                    range.setStart(node, start);
                    range.setEnd(node, start + needle.length);
                    return range.compareBoundaryPoints(Range.START_TO_START, selectedRange) === 0
                        && range.compareBoundaryPoints(Range.END_TO_END, selectedRange) === 0;
                } catch (_) {
                    return false;
                }
            }

            var walker = document.createTreeWalker(
                document.body,
                NodeFilter.SHOW_TEXT,
                {
                    acceptNode: function(node) {
                        return acceptsTextNode(node)
                            ? NodeFilter.FILTER_ACCEPT
                            : NodeFilter.FILTER_REJECT;
                    }
                }
            );

            var node;
            while ((node = walker.nextNode())) {
                var text = node.nodeValue || '';
                var haystack = text.toLocaleLowerCase();
                var searchStart = 0;
                while (true) {
                    var matchStart = haystack.indexOf(needleLower, searchStart);
                    if (matchStart === -1) { break; }
                    count += 1;
                    if (selectedIndex === null && isSelectedMatch(node, matchStart)) {
                        selectedIndex = count;
                    }
                    searchStart = matchStart + Math.max(needle.length, 1);
                }
            }

            return { count: count, selectedIndex: selectedIndex };
        })(\(queryLiteral));
        """
    }

    // MARK: - Navigation history

    private var canGoBackInNavigationHistory: Bool {
        guard let navigationHistoryIndex else { return false }
        return navigationHistoryIndex > 0
    }

    private var canGoForwardInNavigationHistory: Bool {
        guard let navigationHistoryIndex else { return false }
        guard !navigationHistory.isEmpty else { return false }
        return navigationHistoryIndex < navigationHistory.index(before: navigationHistory.endIndex)
    }

    private func loadHistoryEntry(offset: Int) {
        guard let navigationHistoryIndex else { return }
        let nextIndex = navigationHistoryIndex + offset
        guard navigationHistory.indices.contains(nextIndex) else { return }

        pendingHistoryLoadIndex = nextIndex
        webView.load(URLRequest(url: navigationHistory[nextIndex]))
    }

    private func recordNavigationURL(_ url: URL) {
        defer {
            updateBackForwardAvailability()
        }

        guard !navigationHistory.isEmpty, let navigationHistoryIndex else {
            navigationHistory = [url]
            navigationHistoryIndex = 0
            return
        }

        if navigationHistory.indices.contains(navigationHistoryIndex),
           navigationHistory[navigationHistoryIndex] == url {
            return
        }

        if let pendingHistoryLoadIndex,
           navigationHistory.indices.contains(pendingHistoryLoadIndex),
           navigationHistory[pendingHistoryLoadIndex] == url {
            self.navigationHistoryIndex = pendingHistoryLoadIndex
            self.pendingHistoryLoadIndex = nil
            return
        }

        self.pendingHistoryLoadIndex = nil

        let previousIndex = navigationHistoryIndex - 1
        if navigationHistory.indices.contains(previousIndex),
           navigationHistory[previousIndex] == url {
            self.navigationHistoryIndex = previousIndex
            return
        }

        let nextIndex = navigationHistoryIndex + 1
        if navigationHistory.indices.contains(nextIndex),
           navigationHistory[nextIndex] == url {
            self.navigationHistoryIndex = nextIndex
            return
        }

        let insertionIndex = navigationHistory.index(after: navigationHistoryIndex)
        if insertionIndex < navigationHistory.endIndex {
            navigationHistory.removeSubrange(insertionIndex...)
        }
        navigationHistory.append(url)
        self.navigationHistoryIndex = navigationHistory.index(before: navigationHistory.endIndex)
    }

    private func updateBackForwardAvailability() {
        let canGoBack = usesRestoredNavigationHistoryFallback
            ? canGoBackInNavigationHistory
            : webView.canGoBack || canGoBackInNavigationHistory
        let canGoForward = usesRestoredNavigationHistoryFallback
            ? canGoForwardInNavigationHistory
            : webView.canGoForward || canGoForwardInNavigationHistory

        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }

    // MARK: - KVO observers

    private func setUpWebViewObservers() {
        observations.append(
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    self?.estimatedProgress = webView.estimatedProgress
                    self?.onStateChange?()
                }
            }
        )

        observations.append(
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    self?.isLoading = webView.isLoading
                    self?.onStateChange?()
                }
            }
        )

        observations.append(
            webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pageTitle = webView.title ?? self.currentURL?.host ?? "Untitled"
                    self.onStateChange?()
                }
            }
        )

        observations.append(
            webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.currentURL = webView.url
                    if let currentURL = self.currentURL {
                        self.recordNavigationURL(currentURL)
                    } else {
                        self.updateBackForwardAvailability()
                    }
                    self.faviconURL = self.currentURL
                    self.refreshCurrentSitePermissionEntries()
                    self.onStateChange?()
                }
            }
        )

        observations.append(
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    self?.updateBackForwardAvailability()
                    self?.onStateChange?()
                }
            }
        )

        observations.append(
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    self?.updateBackForwardAvailability()
                    self?.onStateChange?()
                }
            }
        )
    }
}

extension WebTabViewModel: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in
            isLoading = true
            // Reset scroll offset to 0 for the new page.
            handleScrollMessage(0)
            resetFindResultsForPageChange()
            onStateChange?()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            isLoading = false
            pageTitle = webView.title ?? currentURL?.host ?? "Untitled"
            updateBackForwardAvailability()
            if isFindBarVisible, !findQuery.isEmpty {
                performFind(backwards: false, resetsIndex: true)
            }
            onStateChange?()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            isLoading = false
            updateBackForwardAvailability()
            onStateChange?()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            isLoading = false
            updateBackForwardAvailability()
            onStateChange?()
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }

        if navigationAction.shouldPerformDownload {
            return .download
        }

        let isLinkActivation = navigationAction.navigationType == .linkActivated
        let opensNewWindow = navigationAction.targetFrame == nil
        let isCommandClick = isLinkActivation && navigationAction.modifierFlags.contains(.command)
        let isMiddleClick = isLinkActivation && navigationAction.buttonNumber == 2

        guard opensNewWindow || isCommandClick || isMiddleClick else { return .allow }

        if opensNewWindow && !isLinkActivation {
            let requestOriginURL = navigationAction.sourceFrame.request.url
            guard shouldAllowScriptedPopup(to: url, requestedBy: requestOriginURL) else {
                return .cancel
            }
        }

        openInNewTab(url, activates: !(isCommandClick || isMiddleClick))
        return .cancel
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        downloadManager.begin(
            download,
            sourceURL: navigationAction.request.url,
            workspaceID: downloadWorkspaceID
        )
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        downloadManager.begin(
            download,
            sourceURL: navigationResponse.response.url,
            workspaceID: downloadWorkspaceID
        )
    }
}

extension WebTabViewModel: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            if navigationAction.navigationType != .linkActivated {
                let requestOriginURL = navigationAction.sourceFrame.request.url
                guard shouldAllowScriptedPopup(to: url, requestedBy: requestOriginURL) else {
                    return nil
                }
            }

            let isBackgroundOpen =
                navigationAction.modifierFlags.contains(.command) ||
                navigationAction.buttonNumber == 2
            openInNewTab(url, activates: !isBackgroundOpen)
        }

        return nil
    }

    func webView(
        _ webView: WKWebView,
        decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
        initiatedBy frame: WKFrameInfo,
        type: WKMediaCaptureType
    ) async -> WKPermissionDecision {
        guard let siteOrigin = SitePermissionOrigin(securityOrigin: origin) else {
            return .deny
        }

        let kinds = SitePermissionKind.mediaKinds(for: type)
        if let storedDecision = mediaCaptureDecision(for: siteOrigin, kinds: kinds) {
            return storedDecision
        }

        let actionDescription = kinds.map(\.promptName).joined(separator: " and ")
        let decision = presentSitePermissionPrompt(
            origin: siteOrigin,
            kinds: kinds,
            actionDescription: "use \(actionDescription)"
        )
        return decision.isAllowed ? .grant : .deny
    }
}
