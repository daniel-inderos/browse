import SwiftUI
import AppKit

// MARK: - Window configuration + traffic-light alignment

/// Custom NSView that configures the hosting NSWindow for a transparent
/// title bar and continuously repositions the traffic-light buttons so
/// they sit vertically centred with the tab pills.
private final class TrafficLightAlignerView: NSView {

    /// Vertical center-Y (from window top) where the traffic lights should land.
    /// With the vertical sidebar, the traffic lights sit near the top of the sidebar.
    /// Top spacer is 52 pt; centering the lights at ~20 pt from the top of the window.
    static let targetCenterY: CGFloat = 20

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        // Kick an initial alignment after the first layout pass
        DispatchQueue.main.async { [weak self] in self?.alignTrafficLights() }
    }

    override func layout() {
        super.layout()
        alignTrafficLights()
    }

    private func alignTrafficLights() {
        guard let window else { return }

        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type),
                  let container = button.superview else { continue }

            let h = button.frame.height
            let newY: CGFloat
            if container.isFlipped {
                // Flipped: y = 0 is the top of the title-bar view
                newY = Self.targetCenterY - h / 2
            } else {
                newY = container.bounds.height - Self.targetCenterY - h / 2
            }
            if abs(button.frame.origin.y - newY) > 0.5 {
                button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: newY))
            }
        }

        // Prevent the title-bar container from clipping the repositioned buttons
        if let close = window.standardWindowButton(.closeButton),
           let titlebar = close.superview {
            titlebar.wantsLayer = true
            titlebar.layer?.masksToBounds = false
            titlebar.superview?.wantsLayer = true
            titlebar.superview?.layer?.masksToBounds = false
        }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> TrafficLightAlignerView { TrafficLightAlignerView() }
    func updateNSView(_ nsView: TrafficLightAlignerView, context: Context) {}
}

struct BrowserWindow: View {
    @Environment(BrowserViewModel.self) private var browserVM
    @State private var sidebarResizeStartWidth: CGFloat?
    private let intentBarHeight: CGFloat = 52
    private let intentBarRevealHoverHeight: CGFloat = 120

    var body: some View {
        HStack(spacing: 0) {
            // Vertical sidebar with tabs (Arc-style)
            if browserVM.isTabBarVisible {
                HStack(spacing: 0) {
                    TabBarView()
                        .frame(width: browserVM.tabBarWidth)

                    sidebarResizeHandle
                }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // Main content area
            VStack(spacing: 0) {
                // Intent bar
                IntentBarView()
                    .frame(height: browserVM.isIntentBarVisible ? intentBarHeight : 0, alignment: .top)
                    .opacity(browserVM.isIntentBarVisible ? 1 : 0)
                    .zIndex(2)

                // Content area
                Group {
                    if let activeTab = browserVM.activeTab {
                        contentView(for: activeTab)
                            .id(activeTab.id)
                    } else {
                        newTabPage
                    }
                }
                .transition(.opacity)
            }
            .overlay(alignment: .top) {
                // Invisible hover strip along the top edge.
                // When the intent bar is hidden and the cursor reaches
                // this zone, the bar slides back into view.
                Rectangle()
                    .fill(Color.primary.opacity(0.001))
                    .frame(
                        height: browserVM.isIntentBarVisible
                            ? 16
                            : intentBarRevealHoverHeight
                    )
                    .onHover { isHovering in
                        browserVM.setIntentBarRevealZoneHovering(isHovering)
                    }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .ignoresSafeArea()
        .background(WindowAccessor())
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.18), value: browserVM.isTabBarVisible)
        .animation(.easeOut(duration: 0.18), value: browserVM.isIntentBarVisible)
    }

    private var sidebarResizeHandle: some View {
        Rectangle()
            // Keep this view hittable so drag is captured reliably.
            .fill(Color.primary.opacity(0.001))
            .frame(width: 16)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if sidebarResizeStartWidth == nil {
                            sidebarResizeStartWidth = browserVM.tabBarWidth
                        }

                        if let startWidth = sidebarResizeStartWidth {
                            browserVM.setTabBarWidth(startWidth + value.translation.width)
                        }
                    }
                    .onEnded { _ in
                        sidebarResizeStartWidth = nil
                    }
            )
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(BrowseColor.borderSubtle)
                    .frame(width: 0.5)
            }
    }

    @ViewBuilder
    private func contentView(for tab: Tab) -> some View {
        switch tab.kind {
        case .web:
            if let webVM = tab.webTabViewModel {
                ZStack {
                    WebTabView(viewModel: webVM)

                    // Show the new tab page until the user navigates somewhere
                    if webVM.currentURL == nil {
                        newTabPage
                            .transition(.opacity.animation(.easeOut(duration: 0.25)))
                    }

                    // Floating AI chat pane (self-positioning via GeometryReader)
                    if browserVM.isChatPaneVisible, let chatVM = browserVM.chatViewModel {
                        ChatPaneView(
                            viewModel: chatVM,
                            initialOffset: browserVM.chatPaneOffset,
                            initialWidth: browserVM.chatPaneWidth,
                            initialHeight: browserVM.chatPaneHeight,
                            onGeometryCommit: { offset, width, height in
                                browserVM.setChatPaneGeometry(offset: offset, width: width, height: height)
                            },
                            onClear: {
                                browserVM.clearChatForCurrentPage()
                            },
                            onClose: {
                                browserVM.closeChatPane()
                            }
                        )
                        .transition(.opacity)
                    }
                }
                .animation(.spring(response: 0.26, dampingFraction: 0.86), value: browserVM.isChatPaneVisible)
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

    // MARK: - New Tab Page

    private var newTabPage: some View {
        ZStack {
            newTabBackground
            VStack(spacing: 16) {
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
