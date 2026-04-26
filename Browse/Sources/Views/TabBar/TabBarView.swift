import AppKit
import SwiftUI

struct TabBarView: View {
    @Environment(BrowserViewModel.self) private var browserVM

    // MARK: - Drag-to-Reorder State

    @State private var draggingTabID: UUID?
    @State private var dragOffset: CGFloat = 0

    // Row-height estimates (padding + content + spacing) used as swap thresholds.
    private let compactRowHeight: CGFloat = 26
    private let regularRowHeight: CGFloat = 34

    private let tabTransition = AnyTransition.asymmetric(
        insertion: .scale(scale: 0.94).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
    )
    private let tabListAnimation = Animation.spring(response: 0.26, dampingFraction: 0.86)

    // MARK: - Sectioned Tab Lists

    private var pinnedTabs: [Tab] {
        browserVM.tabs.filter { $0.isPinned }
    }

    private var todayTabs: [Tab] {
        browserVM.tabs.filter { !$0.isPinned && Calendar.current.isDateInToday($0.lastAccessedAt) }
    }

    private var earlierTabs: [Tab] {
        browserVM.tabs.filter { !$0.isPinned && !Calendar.current.isDateInToday($0.lastAccessedAt) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TrafficLightControls()
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 52, alignment: .topLeading)

            // Vertical scrollable tab list — sectioned
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    // --- Pinned Section ---
                    if !pinnedTabs.isEmpty {
                        sectionHeader("Pinned")
                        ForEach(pinnedTabs) { tab in
                            tabItem(tab, compact: true)
                                .transition(tabTransition)
                        }
                        sectionDivider
                    }

                    // --- Today Section ---
                    if !todayTabs.isEmpty {
                        sectionHeader("Today")
                        ForEach(todayTabs) { tab in
                            tabItem(tab, compact: false)
                                .transition(tabTransition)
                        }
                        if !earlierTabs.isEmpty {
                            sectionDivider
                        }
                    }

                    // --- Earlier Section ---
                    if !earlierTabs.isEmpty {
                        sectionHeader("Earlier")
                        ForEach(earlierTabs) { tab in
                            tabItem(tab, compact: false)
                                .transition(tabTransition)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .animation(tabListAnimation, value: browserVM.tabs.map(\.isPinned))
            }

            Spacer(minLength: 0)

            // New tab button — pinned at the bottom of the sidebar
            Button(action: { browserVM.newTab() }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("New Tab")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .background(BrowseColor.tabBarBackground)
    }

    // MARK: - Section Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(BrowseFont.badge)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 3)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 0.5)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }

    // MARK: - Tab Item with Drag-to-Reorder

    private func tabItem(_ tab: Tab, compact: Bool) -> some View {
        let isDragging = draggingTabID == tab.id
        let rowHeight = compact ? compactRowHeight : regularRowHeight

        return TabItemView(
            tab: tab,
            isActive: tab.id == browserVM.activeTabID,
            compact: compact,
            onSelect: {
                // Suppress selection while a drag is active to avoid
                // the Button firing on mouse-up at the end of a drag.
                guard draggingTabID == nil else { return }
                browserVM.selectTab(tab.id)
            },
            onClose: { browserVM.closeTab(tab.id) },
            onCloseOthers: { browserVM.closeOtherTabs(keeping: tab.id) },
            onCloseTabsBelow: { browserVM.closeTabsBelow(tab.id) },
            onCopyURL: {
                guard let url = tab.webTabViewModel?.currentURL ?? tab.url else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(url.absoluteString, forType: .string)
            },
            onDuplicate: { browserVM.duplicateTab(tab.id) },
            onTogglePin: { browserVM.togglePin(tab.id) }
        )
        // --- Visual feedback for the dragged item ---
        .offset(y: isDragging ? dragOffset : 0)
        .scaleEffect(isDragging ? 1.035 : 1.0)
        .shadow(
            color: .black.opacity(isDragging ? 0.18 : 0),
            radius: isDragging ? 10 : 0,
            y: isDragging ? 3 : 0
        )
        .zIndex(isDragging ? 100 : 0)
        // The dragged item opts out of the implicit layout animation so its
        // position is entirely controlled by dragOffset (no double-animation).
        // All other items get the spring so they slide out of the way.
        .animation(
            isDragging ? nil : tabListAnimation,
            value: browserVM.tabs.map(\.id)
        )
        .simultaneousGesture(reorderGesture(for: tab, rowHeight: rowHeight))
    }

    // MARK: - Drag Gesture

    private func reorderGesture(for tab: Tab, rowHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                // First touch — "lift" the tab with a short ease
                if draggingTabID == nil {
                    withAnimation(.easeOut(duration: 0.15)) {
                        draggingTabID = tab.id
                    }
                }
                guard draggingTabID == tab.id else { return }

                dragOffset = value.translation.height

                // When the gesture crosses ≈ half a row, perform a live swap
                // and snap the offset back by one row so tracking stays correct.
                let threshold = rowHeight * 0.55
                if dragOffset > threshold {
                    if performSwap(tab.id, direction: .down) {
                        dragOffset -= rowHeight
                    }
                } else if dragOffset < -threshold {
                    if performSwap(tab.id, direction: .up) {
                        dragOffset += rowHeight
                    }
                }
            }
            .onEnded { _ in
                browserVM.commitTabReorder()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    draggingTabID = nil
                    dragOffset = 0
                }
            }
    }

    // MARK: - Swap Logic

    private enum SwapDirection { case up, down }

    private func performSwap(_ tabID: UUID, direction: SwapDirection) -> Bool {
        guard let sourceIndex = browserVM.tabs.firstIndex(where: { $0.id == tabID }) else {
            return false
        }
        let targetIndex = direction == .down ? sourceIndex + 1 : sourceIndex - 1
        guard targetIndex >= 0, targetIndex < browserVM.tabs.count else {
            return false
        }

        let sourceTab = browserVM.tabs[sourceIndex]
        let targetTab = browserVM.tabs[targetIndex]

        // Only allow reorder within the same visual section.
        guard sameDragSection(sourceTab, targetTab) else { return false }

        // Swap without wrapping in withAnimation — the per-item implicit
        // .animation(tabListAnimation, value: tabs.map(\.id)) drives
        // the spring for every *non*-dragged item automatically.
        browserVM.tabs.swapAt(sourceIndex, targetIndex)
        return true
    }

    /// Two tabs belong to the same drag section when they share pinned state
    /// and, for unpinned tabs, the same "today vs earlier" grouping.
    private func sameDragSection(_ a: Tab, _ b: Tab) -> Bool {
        guard a.isPinned == b.isPinned else { return false }
        if a.isPinned { return true }
        return Calendar.current.isDateInToday(a.lastAccessedAt)
            == Calendar.current.isDateInToday(b.lastAccessedAt)
    }
}

private struct TrafficLightControls: View {
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            trafficLight(
                color: Color(red: 1.0, green: 0.36, blue: 0.33),
                symbol: "xmark",
                accessibilityLabel: "Close",
                action: { activeWindow?.performClose(nil) }
            )

            trafficLight(
                color: Color(red: 1.0, green: 0.76, blue: 0.10),
                symbol: "minus",
                accessibilityLabel: "Minimize",
                action: { activeWindow?.miniaturize(nil) }
            )

            trafficLight(
                color: Color(red: 0.13, green: 0.80, blue: 0.27),
                symbol: "plus",
                accessibilityLabel: "Zoom",
                action: { activeWindow?.zoom(nil) }
            )
        }
        .padding(.top, 13)
        .padding(.leading, 20)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var activeWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow
    }

    private func trafficLight(
        color: Color,
        symbol: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 13, height: 13)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 5.5, weight: .heavy))
                        .foregroundStyle(Color.black.opacity(0.58))
                        .opacity(isHovering ? 1 : 0)
                }
                .overlay {
                    Circle()
                        .strokeBorder(Color.black.opacity(0.16), lineWidth: 0.5)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
