import SwiftUI
import WebKit

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

// MARK: - WebTabViewModel

@MainActor
@Observable
final class WebTabViewModel: NSObject {
    var currentURL: URL?
    var pageTitle: String = "New Tab"
    var isLoading: Bool = false
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var estimatedProgress: Double = 0
    var faviconURL: URL?
    var onStateChange: (() -> Void)?
    var onScrollPositionChange: ((CGFloat) -> Void)?

    private(set) var webView: WKWebView
    private var observations: [NSKeyValueObservation] = []
    private(set) var scrollOffsetY: CGFloat = 0

    /// Prevent the handler from being collected while the content controller retains it.
    private var scrollHandler: ScrollMessageHandler?

    override init() {
        let config = WKWebViewConfiguration()
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

        self.webView = WKWebView(frame: .zero, configuration: config)
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

        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = Self.desktopSafariUserAgent
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

    func navigate(to url: URL) {
        let request = URLRequest(url: url)
        webView.load(request)
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func reloadFromOrigin() { webView.reloadFromOrigin() }
    func stopLoading() { webView.stopLoading() }

    // MARK: - Scroll handling

    private func handleScrollMessage(_ offsetY: CGFloat) {
        guard abs(offsetY - scrollOffsetY) > 0.5 else { return }
        scrollOffsetY = offsetY
        onScrollPositionChange?(offsetY)
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
                    if let host = self.currentURL?.host {
                        self.faviconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32")
                    } else {
                        self.faviconURL = nil
                    }
                    self.onStateChange?()
                }
            }
        )

        observations.append(
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    self?.canGoBack = webView.canGoBack
                    self?.onStateChange?()
                }
            }
        )

        observations.append(
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    self?.canGoForward = webView.canGoForward
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
            onStateChange?()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            isLoading = false
            pageTitle = webView.title ?? currentURL?.host ?? "Untitled"
            canGoBack = webView.canGoBack
            canGoForward = webView.canGoForward
            onStateChange?()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            isLoading = false
            canGoBack = webView.canGoBack
            canGoForward = webView.canGoForward
            onStateChange?()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            isLoading = false
            onStateChange?()
        }
    }

    nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        .allow
    }
}
