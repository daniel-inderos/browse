import SwiftUI
import AppKit

// MARK: - Window configuration + traffic-light alignment

/// Custom NSView that configures the hosting NSWindow for a transparent
/// title bar. Browse hosts the native traffic-light buttons in the sidebar
/// when that sidebar is visible, and otherwise keeps the titlebar copy hidden.
@MainActor
private final class TrafficLightAlignerView: NSView {
    private static let fallbackFrameDefaultsKey = "Browse.LastWindowFrame"
    private static let windowButtonTypes: [NSWindow.ButtonType] = [
        .closeButton,
        .miniaturizeButton,
        .zoomButton
    ]

    var onWindowWillClose: (() -> Void)?

    private let frameDefaultsKey: String
    private weak var observedWindow: NSWindow?
    private var windowObservers: [NSObjectProtocol] = []
    private var pendingFrame: NSRect?
    private var didRestoreInitialFrame = false

    init(windowID: UUID) {
        frameDefaultsKey = "Browse.WindowFrame.\(windowID.uuidString)"
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeWindowObservers()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.isRestorable = false
        prepareFrameRestoration(for: window)
        observeWindowNotifications(for: window)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        hideStandardTrafficLights()
        DispatchQueue.main.async { [weak self] in self?.hideStandardTrafficLights() }
    }

    override func layout() {
        super.layout()
        hideStandardTrafficLights()
    }

    private func hideStandardTrafficLights() {
        guard let window else { return }
        let hostViews = trafficLightHostViews(in: window)

        for type in Self.windowButtonTypes {
            guard let button = window.standardWindowButton(type) else { continue }
            guard !(button.superview is NativeTrafficLightContainerView) else { continue }
            button.isHidden = true
            button.alphaValue = 0
        }

        for hostView in hostViews {
            guard !(hostView is NativeTrafficLightContainerView) else { continue }
            hostView.isHidden = true
            hostView.alphaValue = 0
            hostView.wantsLayer = true
            hostView.layer?.backgroundColor = NSColor.clear.cgColor
            hostView.layer?.masksToBounds = false
        }
    }

    private func trafficLightHostViews(in window: NSWindow) -> [NSView] {
        var seenIDs = Set<ObjectIdentifier>()
        return Self.windowButtonTypes.compactMap { type in
            guard let hostView = window.standardWindowButton(type)?.superview else { return nil }
            let id = ObjectIdentifier(hostView)
            guard seenIDs.insert(id).inserted else { return nil }
            return hostView
        }
    }

    private func prepareFrameRestoration(for window: NSWindow) {
        let defaults = UserDefaults.standard
        let savedFrame = defaults.string(forKey: frameDefaultsKey)
            ?? defaults.string(forKey: Self.fallbackFrameDefaultsKey)
        pendingFrame = savedFrame.flatMap { restoredFrame(from: $0, for: window) }
        didRestoreInitialFrame = false

        // SwiftUI applies its default window size after the hosting view is attached.
        // Restore on the next run-loop turn so our saved geometry wins that race.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.restoreInitialFrameIfNeeded(for: window)
        }
    }

    private func restoreInitialFrameIfNeeded(for window: NSWindow) {
        guard !didRestoreInitialFrame else { return }
        didRestoreInitialFrame = true

        if let pendingFrame {
            window.setFrame(pendingFrame, display: true)
            self.pendingFrame = nil
        }
        saveFrame(for: window)
    }

    private func observeWindowNotifications(for window: NSWindow) {
        guard observedWindow !== window else { return }
        removeWindowObservers()
        observedWindow = window

        let center = NotificationCenter.default
        windowObservers.append(center.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            Task { @MainActor [weak self] in
                if let window {
                    self?.saveFrame(for: window)
                }
                self?.onWindowWillClose?()
            }
        })

        windowObservers.append(center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            Task { @MainActor [weak self, weak window] in
                guard let self, let window else { return }
                self.restoreInitialFrameIfNeeded(for: window)
            }
        })

        for notification in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            windowObservers.append(center.addObserver(
                forName: notification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                Task { @MainActor [weak self, weak window] in
                    guard let self, let window else { return }
                    self.saveFrame(for: window)
                }
            })
        }
    }

    private func saveFrame(for window: NSWindow) {
        guard didRestoreInitialFrame else { return }
        guard !window.styleMask.contains(.fullScreen) else { return }

        let frame = NSStringFromRect(window.frame)
        let defaults = UserDefaults.standard
        defaults.set(frame, forKey: frameDefaultsKey)
        defaults.set(frame, forKey: Self.fallbackFrameDefaultsKey)
    }

    private func restoredFrame(from value: String, for window: NSWindow) -> NSRect? {
        let savedFrame = NSRectFromString(value)
        guard savedFrame.width.isFinite, savedFrame.height.isFinite,
              savedFrame.minX.isFinite, savedFrame.minY.isFinite,
              savedFrame.width > 0, savedFrame.height > 0 else {
            return nil
        }

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return savedFrame }

        let bestMatchingScreen = screens.max { first, second in
            intersectionArea(savedFrame, first.visibleFrame)
                < intersectionArea(savedFrame, second.visibleFrame)
        }
        let destinationScreen: NSScreen
        if let bestMatchingScreen,
           intersectionArea(savedFrame, bestMatchingScreen.visibleFrame) > 0 {
            destinationScreen = bestMatchingScreen
        } else {
            destinationScreen = NSScreen.main ?? screens[0]
        }
        let visibleFrame = destinationScreen.visibleFrame
        let minimumSize = window.minSize
        let width = min(max(savedFrame.width, minimumSize.width), visibleFrame.width)
        let height = min(max(savedFrame.height, minimumSize.height), visibleFrame.height)
        let x = min(max(savedFrame.minX, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(savedFrame.minY, visibleFrame.minY), visibleFrame.maxY - height)

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func intersectionArea(_ first: NSRect, _ second: NSRect) -> CGFloat {
        let intersection = first.intersection(second)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private func removeWindowObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
        observedWindow = nil
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let windowID: UUID
    let onWindowWillClose: () -> Void

    func makeNSView(context: Context) -> TrafficLightAlignerView {
        let view = TrafficLightAlignerView(windowID: windowID)
        view.onWindowWillClose = onWindowWillClose
        return view
    }

    func updateNSView(_ nsView: TrafficLightAlignerView, context: Context) {
        nsView.onWindowWillClose = onWindowWillClose
    }
}

private struct WindowSessionRestorer: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                BrowserWindowSessionController.shared.restoreAdditionalWindowsIfNeeded(
                    openWindow: openWindow
                )
            }
    }
}

struct BrowserWindow: View {
    @State private var browserVM: BrowserViewModel
    @State private var sidebarResizeStartWidth: CGFloat?
    @State private var sidebarResizeWidth: CGFloat?
    @State private var navigationKeyEventMonitor: Any?
    @State private var isIntentBarTextFocused = false
    @State private var pageContentOpacity: Double = 1
    @State private var pageFadeSequence = 0
    private let configuration: BrowserWindowConfiguration
    private let intentBarHeight: CGFloat = 42
    private let intentBarRevealHoverHeight: CGFloat = 120
    private let sidebarMinWidth: CGFloat = 180
    private let sidebarMaxWidth: CGFloat = 360
    private let sidebarFadeAnimation: Animation = .easeOut(duration: 0.22)
    private let pageFadeAnimation: Animation = .easeOut(duration: 0.18)

    init(configuration: BrowserWindowConfiguration) {
        self.configuration = configuration
        _browserVM = State(
            initialValue: BrowserViewModel(
                windowID: configuration.id,
                isPrivateBrowsing: configuration.isPrivateBrowsing,
                restoresPersistedState: configuration.restoresPersistedState
            )
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            // Vertical sidebar with tabs (Arc-style)
            if browserVM.isTabBarVisible {
                TabBarView()
                    .frame(width: sidebarResizeWidth ?? browserVM.tabBarWidth)
                    .overlay(alignment: .trailing) {
                        sidebarResizeHandle
                    }
                .transition(.opacity.animation(sidebarFadeAnimation))
            }

            // Main content area
            VStack(spacing: 0) {
                // Intent bar
                if browserVM.activeTab?.kind != .briefing {
                    IntentBarView { focused in
                        isIntentBarTextFocused = focused
                    }
                        .frame(height: browserVM.shouldShowIntentBar ? intentBarHeight : 0, alignment: .top)
                        .opacity(browserVM.shouldShowIntentBar ? 1 : 0)
                        .zIndex(2)
                }

                // Content area
                Group {
                    if let activeTab = browserVM.activeTab {
                        contentView(for: activeTab)
                            .id(activeTab.id)
                    } else {
                        newTabPage
                    }
                }
                .opacity(pageContentOpacity)
                .transition(.opacity)
            }
            .overlay(alignment: .top) {
                // Invisible hover strip along the top edge.
                // When the intent bar is hidden and the cursor reaches
                // this zone, the bar slides back into view.
                if browserVM.activeTab?.kind != .briefing {
                    Rectangle()
                        .fill(Color.primary.opacity(0.001))
                        .frame(
                            height: browserVM.shouldShowIntentBar
                                ? 16
                                : intentBarRevealHoverHeight
                        )
                        .onHover { isHovering in
                            browserVM.setIntentBarRevealZoneHovering(isHovering)
                        }
                }
            }
            .overlay(alignment: .top) {
                if browserVM.isPageZoomIndicatorVisible,
                   let zoomText = browserVM.pageZoomIndicatorText {
                    pageZoomIndicator(zoomText)
                        .padding(.top, browserVM.shouldShowIntentBar ? 54 : 14)
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
                        )
                }
            }
            .overlay(alignment: .topTrailing) {
                if browserVM.isCurrentURLCopyIndicatorVisible {
                    copiedURLIndicator
                        .padding(.top, browserVM.shouldShowIntentBar ? 52 : 12)
                        .padding(.trailing, 14)
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing))
                        )
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .ignoresSafeArea()
        .environment(browserVM)
        .focusedSceneValue(\.browserViewModel, browserVM)
        .background(
            WindowAccessor(windowID: configuration.id) {
                BrowserWindowSessionController.shared.unregisterClosedWindow(
                    configuration: configuration
                )
            }
        )
        .background(WindowSessionRestorer())
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeOut(duration: 0.18), value: browserVM.shouldShowIntentBar)
        .animation(.easeOut(duration: 0.16), value: browserVM.isCurrentURLCopyIndicatorVisible)
        .animation(.easeOut(duration: 0.16), value: browserVM.isPageZoomIndicatorVisible)
        .onChange(of: browserVM.isTabBarVisible) { _, _ in
            fadePageContentForSidebarChange()
        }
        .onChange(of: browserVM.isChatPaneVisible) { _, _ in
            fadePageContentForSidebarChange()
        }
        .onAppear {
            BrowserWindowSessionController.shared.registerOpenWindow(configuration: configuration)
            installNavigationKeyEventMonitor()
        }
        .onDisappear {
            removeNavigationKeyEventMonitor()
        }
    }

    private var copiedURLIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))

            Text("Copied")
                .font(BrowseFont.badge)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(BrowseColor.success)
                .shadow(color: Color.black.opacity(0.14), radius: 10, y: 4)
        )
        .accessibilityLabel("Current URL copied")
    }

    private func pageZoomIndicator(_ zoomText: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 12, weight: .semibold))

            Text(zoomText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.14), radius: 12, y: 5)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(BrowseColor.borderSubtle, lineWidth: 0.5)
        )
        .accessibilityLabel("Page zoom \(zoomText)")
    }

    private func installNavigationKeyEventMonitor() {
        guard navigationKeyEventMonitor == nil else { return }
        navigationKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleNavigationKeyDown(event)
        }
    }

    private func removeNavigationKeyEventMonitor() {
        if let navigationKeyEventMonitor {
            NSEvent.removeMonitor(navigationKeyEventMonitor)
            self.navigationKeyEventMonitor = nil
        }
    }

    private func handleNavigationKeyDown(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53, browserVM.isFindBarVisibleInActiveTab {
            browserVM.closeFindInActiveTab()
            return nil
        }

        let shortcutFlags: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        let flags = event.modifierFlags.intersection(shortcutFlags)
        guard flags == .command else { return event }
        guard NSApp.keyWindow != nil else { return event }
        guard browserVM.activeTab?.kind == .web else { return event }

        if event.charactersIgnoringModifiers?.lowercased() == "f" {
            guard browserVM.canFindInActiveTab else { return event }
            browserVM.showFindInActiveTab()
            return nil
        }

        guard !isIntentBarTextFocused else { return event }

        switch event.keyCode {
        case 123: // left arrow
            browserVM.goBackInActiveTab()
            return nil
        case 124: // right arrow
            browserVM.goForwardInActiveTab()
            return nil
        default:
            return event
        }
    }

    private var sidebarResizeHandle: some View {
        Rectangle()
            // Keep this view hittable so drag is captured reliably.
            .fill(Color.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if sidebarResizeStartWidth == nil {
                            sidebarResizeStartWidth = browserVM.tabBarWidth
                        }

                        if let startWidth = sidebarResizeStartWidth {
                            var transaction = Transaction(animation: nil)
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                sidebarResizeWidth = max(
                                    sidebarMinWidth,
                                    min(startWidth + value.translation.width, sidebarMaxWidth)
                                )
                            }
                        }
                    }
                    .onEnded { _ in
                        if let sidebarResizeWidth {
                            browserVM.setTabBarWidth(sidebarResizeWidth)
                        }
                        sidebarResizeStartWidth = nil
                        sidebarResizeWidth = nil
                    }
            )
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    @ViewBuilder
    private func contentView(for tab: Tab) -> some View {
        switch tab.kind {
        case .web:
            if let webVM = tab.webTabViewModel {
                HStack(spacing: 0) {
                    Group {
                        if webVM.currentURL == nil {
                            newTabPage
                                .transition(.opacity.animation(.easeOut(duration: 0.25)))
                        } else {
                            WebTabView(viewModel: webVM)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Page chat lives as a right sidebar alongside web content.
                    if webVM.currentURL != nil,
                       browserVM.isChatPaneVisible,
                       let chatVM = browserVM.chatViewModel {
                        ChatPaneView(
                            viewModel: chatVM,
                            tabMentionCandidates: browserVM.chatTabMentionCandidates,
                            initialWidth: browserVM.chatPaneWidth,
                            onAttachTabMention: { candidate in
                                await browserVM.attachTabMentionToChat(candidate)
                            },
                            onWidthCommit: { width in
                                browserVM.setChatPaneWidth(width)
                            },
                            onClear: {
                                browserVM.clearChatForCurrentPage()
                            },
                            onClose: {
                                browserVM.closeChatPane()
                            }
                        )
                        .transition(.opacity.animation(sidebarFadeAnimation))
                    }
                }
            } else {
                newTabPage
            }

        case .briefing:
            if let briefingVM = tab.briefingViewModel {
                BriefingPageView(viewModel: briefingVM, tabID: tab.id, onSourceTap: { url in
                    browserVM.openSourceInNewTab(url)
                })
            } else {
                newTabPage
            }
        }
    }

    private func fadePageContentForSidebarChange() {
        pageFadeSequence += 1
        let currentSequence = pageFadeSequence

        withAnimation(pageFadeAnimation) {
            pageContentOpacity = 0.58
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard pageFadeSequence == currentSequence else { return }

            withAnimation(pageFadeAnimation) {
                pageContentOpacity = 1
            }
        }
    }

    // MARK: - New Tab Page

    private var newTabPage: some View {
        ZStack {
            newTabBackground
            VStack(spacing: 16) {
                if browserVM.isPrivateBrowsing {
                    Label("Private Browsing", systemImage: "eye.slash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BrowseColor.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(BrowseColor.accent.opacity(0.08))
                        )
                }

                Text(greetingMessage)
                    .font(.system(size: 48, weight: .semibold, design: .serif))
                    .foregroundStyle(.primary.opacity(0.85))

                Text(dateString)
                    .font(.system(size: 15, weight: .medium, design: .default))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .tracking(1.0)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var newTabBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            RadialGradient(
                colors: [
                    BrowseColor.accent.opacity(0.04),
                    Color.clear,
                ],
                center: .top,
                startRadius: 0,
                endRadius: 500
            )
        }
    }

    private var greetingMessage: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning."
        case 12..<17: return "Good afternoon."
        case 17..<22: return "Good evening."
        default:      return "Burning the midnight oil."
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date()).uppercased()
    }
}
