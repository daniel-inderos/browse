import AppKit
import SwiftUI

struct TabBarView: View {
    @Environment(BrowserViewModel.self) private var browserVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Drag-to-Reorder State

    @State private var draggingTabID: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var groupIDsBeingRenamed: Set<UUID> = []
    @State private var pendingGroupTitle = ""
    @State private var isRenameGroupAlertPresented = false
    @State private var dropTargetGroupID: UUID?
    @State private var workspaceIDBeingRenamed: UUID?
    @State private var pendingWorkspaceName = ""
    @State private var isRenameWorkspaceAlertPresented = false
    @State private var pendingNewWorkspaceName = ""
    @State private var isCreateWorkspaceAlertPresented = false
    @State private var isWorkspaceSwitcherPresented = false
    @State private var isPointerOverTabList = false
    @State private var workspaceSwipeProgress: CGFloat = 0

    // Row-height estimates (padding + content + spacing) used as swap thresholds.
    private let compactRowHeight: CGFloat = 26
    private let regularRowHeight: CGFloat = 34

    private let tabTransition = AnyTransition.asymmetric(
        insertion: .scale(scale: 0.94).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
    )
    private let tabListAnimation = Animation.spring(response: 0.26, dampingFraction: 0.86)

    private var workspaceSwitchAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .smooth(duration: 0.28, extraBounce: 0)
    }

    private var workspaceSlideDistance: CGFloat {
        reduceMotion ? 0 : 36
    }

    // MARK: - Sectioned Tab Lists

    private var favoriteTabs: [Tab] {
        browserVM.tabs.filter { $0.isFavorite }
    }

    private var pinnedTabs: [Tab] {
        browserVM.tabs.filter { $0.isPinned && !$0.isFavorite }
    }

    private var todayTabs: [Tab] {
        browserVM.tabs.filter {
            !$0.isFavorite && !$0.isPinned && $0.groupID == nil
                && Calendar.current.isDateInToday($0.lastAccessedAt)
        }
    }

    private var earlierTabs: [Tab] {
        browserVM.tabs.filter {
            !$0.isFavorite && !$0.isPinned && $0.groupID == nil
                && !Calendar.current.isDateInToday($0.lastAccessedAt)
        }
    }

    private var hasStandardTabs: Bool {
        !pinnedTabs.isEmpty || !browserVM.tabGroups.isEmpty || !todayTabs.isEmpty || !earlierTabs.isEmpty
    }

    private var favoriteGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 7), count: 3)
    }

    var body: some View {
        VStack(spacing: 0) {
            NativeTrafficLightControls()
                .frame(width: 60, height: 20)
                .padding(.top, 12)
                .padding(.leading, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 52, alignment: .topLeading)

            // Vertical scrollable tab list — sectioned
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    // --- Favorites Section ---
                    if !favoriteTabs.isEmpty {
                        LazyVGrid(columns: favoriteGridColumns, spacing: 7) {
                            ForEach(favoriteTabs) { tab in
                                favoriteTabItem(tab)
                                    .transition(tabTransition)
                            }
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 8)

                        sectionDivider
                    }

                    // --- Pinned Section ---
                    if !pinnedTabs.isEmpty {
                        sectionHeader("Pinned")
                        ForEach(pinnedTabs) { tab in
                            tabItem(tab, compact: true)
                                .transition(tabTransition)
                        }
                        sectionDivider
                    }

                    // --- Folder / Tab Group Sections ---
                    if !browserVM.tabGroups.isEmpty {
                        ForEach(browserVM.tabGroups) { group in
                            tabGroupSection(group)
                                .transition(tabTransition)
                        }
                        if !todayTabs.isEmpty || !earlierTabs.isEmpty {
                            sectionDivider
                        }
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
                .animation(tabListAnimation, value: browserVM.tabs.map(\.isFavorite))
                .animation(tabListAnimation, value: browserVM.tabs.map(\.groupID))
                .animation(tabListAnimation, value: browserVM.tabGroups)
                // Tracks whether the pointer is on tab content so horizontal
                // swipes only switch workspaces from the sidebar's empty area.
                .onHover { isPointerOverTabList = $0 }
            }
            .id(browserVM.activeWorkspaceID)
            .transition(workspaceSlideTransition)
            .offset(x: workspaceSwipeProgress * workspaceSlideDistance)
            .opacity(1 - Double(abs(workspaceSwipeProgress)) * 0.08)

            Spacer(minLength: 0)

            if !browserVM.isPrivateBrowsing {
                workspaceDock
            }

            bottomToolbar
        }
        .animation(workspaceSwitchAnimation, value: browserVM.activeWorkspaceID)
        .background(BrowseColor.tabBarBackground)
        .background(
            WorkspaceSwipeMonitor(
                isPointerOverTabList: isPointerOverTabList,
                isEnabled: !browserVM.isPrivateBrowsing && browserVM.workspaces.count > 1,
                onSwipeProgress: { updateWorkspaceSwipeProgress($0) },
                onSwipeEnd: { settleWorkspaceSwipe() },
                onSwipeLeft: {
                    commitWorkspaceSwipe { browserVM.selectNextWorkspace() }
                },
                onSwipeRight: {
                    commitWorkspaceSwipe { browserVM.selectPreviousWorkspace() }
                }
            )
        )
        .alert(renameFolderAlertTitle, isPresented: $isRenameGroupAlertPresented) {
            TextField("Folder Name", text: $pendingGroupTitle)
            Button("Cancel", role: .cancel) {
                groupIDsBeingRenamed = []
            }
            Button("Rename") {
                browserVM.renameTabGroups(groupIDsBeingRenamed, title: pendingGroupTitle)
                groupIDsBeingRenamed = []
            }
        } message: {
            if groupIDsBeingRenamed.count > 1 {
                Text("All selected folders will use this name.")
            }
        }
        .alert("Rename Workspace", isPresented: $isRenameWorkspaceAlertPresented) {
            TextField("Workspace Name", text: $pendingWorkspaceName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let workspaceIDBeingRenamed {
                    browserVM.renameWorkspace(workspaceIDBeingRenamed, name: pendingWorkspaceName)
                }
                workspaceIDBeingRenamed = nil
            }
        }
        .alert("New Workspace", isPresented: $isCreateWorkspaceAlertPresented) {
            TextField("Workspace Name", text: $pendingNewWorkspaceName)
            Button("Cancel", role: .cancel) {
                pendingNewWorkspaceName = ""
            }
            Button("Create") {
                let name = pendingNewWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
                browserVM.createWorkspace(named: name.isEmpty ? browserVM.suggestedWorkspaceName() : name)
                pendingNewWorkspaceName = ""
            }
        }
    }

    // MARK: - Section Components

    /// Slides the tab list toward the direction of the workspace switch.
    private var workspaceSlideTransition: AnyTransition {
        let isForward = browserVM.workspaceSwitchDirection >= 0
        return .asymmetric(
            insertion: .offset(x: isForward ? workspaceSlideDistance : -workspaceSlideDistance)
                .combined(with: .opacity),
            removal: .offset(x: isForward ? -workspaceSlideDistance : workspaceSlideDistance)
                .combined(with: .opacity)
        )
    }

    private func updateWorkspaceSwipeProgress(_ progress: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            workspaceSwipeProgress = progress
        }
    }

    private func settleWorkspaceSwipe() {
        withAnimation(workspaceSwitchAnimation) {
            workspaceSwipeProgress = 0
        }
    }

    private func commitWorkspaceSwipe(_ switchWorkspace: () -> Void) {
        withAnimation(workspaceSwitchAnimation) {
            workspaceSwipeProgress = 0
            switchWorkspace()
        }
    }

    private var workspaceDock: some View {
        HStack(spacing: 6) {
            Button {
                isWorkspaceSwitcherPresented.toggle()
            } label: {
                workspacePill(browserVM.activeWorkspace)
            }
            .buttonStyle(.plain)
            .help("Switch Workspace")
            .popover(isPresented: $isWorkspaceSwitcherPresented, arrowEdge: .top) {
                WorkspaceSwitcherView(
                    onRename: { beginRenaming($0) },
                    onCreate: { beginCreatingWorkspace() },
                    onDismiss: { isWorkspaceSwitcherPresented = false }
                )
            }

            Button {
                beginCreatingWorkspace()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.045))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Workspace")
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
                .padding(.horizontal, 10)
        }
    }

    private var bottomToolbar: some View {
        HStack(spacing: 6) {
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

            Button(action: { browserVM.toggleDownloadsPanel() }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            browserVM.isDownloadsPanelVisible
                                ? BrowseColor.accent
                                : Color.secondary
                        )
                        .frame(width: 34, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .contentShape(Rectangle())

                    if browserVM.downloadManager.activeCount > 0 {
                        Circle()
                            .fill(BrowseColor.accent)
                            .frame(width: 7, height: 7)
                            .offset(x: -7, y: 7)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Downloads")
            .popover(
                isPresented: Binding(
                    get: { browserVM.isDownloadsPanelVisible },
                    set: { isPresented in
                        if isPresented {
                            browserVM.isDownloadsPanelVisible = true
                        } else {
                            browserVM.hideDownloadsPanel()
                        }
                    }
                ),
                arrowEdge: .trailing
            ) {
                DownloadsPanelView(
                    manager: browserVM.downloadManager,
                    activeWorkspaceID: browserVM.activeWorkspaceID,
                    workspaces: browserVM.workspaces,
                    onClose: { browserVM.hideDownloadsPanel() }
                )
            }

            Button(action: { browserVM.createTabGroup() }) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Folder")
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
    }

    private func workspacePill(_ workspace: PersistedWorkspace?) -> some View {
        let accent = workspace?.accentColor ?? BrowseColor.accent
        return HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(accent.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(accent.opacity(0.30), lineWidth: 0.7)
                    )

                Image(systemName: workspace?.iconName ?? "square.grid.2x2")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 22, height: 22)

            Text(workspace?.name ?? "Workspace")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.7)
        )
        .contentShape(Rectangle())
    }

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

    private func tabGroupSection(_ group: TabGroup) -> some View {
        let tabs = groupedTabs(for: group)
        let isDropTargeted = dropTargetGroupID == group.id
        let isMultiSelected = browserVM.selectedGroupIDs.contains(group.id)
        let targetGroupIDs = contextMenuGroupIDs(for: group)
        let targetGroupCount = targetGroupIDs.count
        let selectedFoldersHaveTabs = browserVM.tabs.contains { tab in
            tab.groupID.map(targetGroupIDs.contains) ?? false
        }

        return VStack(spacing: 2) {
            Button {
                // Modified clicks never reach a Button action on macOS;
                // they are handled by the high-priority tap gestures below.
                guard !NSEvent.modifierFlags.contains(.command) else { return }
                browserVM.toggleTabGroupCollapsed(group.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: group.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 10)
                    Image(systemName: group.isCollapsed ? "folder" : "folder.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(group.title)
                        .font(BrowseFont.badge)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text("\(tabs.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 3)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            isMultiSelected
                                ? BrowseColor.accent.opacity(0.14)
                                : (isDropTargeted ? BrowseColor.accent.opacity(0.10) : Color.clear)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isMultiSelected ? BrowseColor.accent.opacity(0.45) : Color.clear,
                            lineWidth: 1
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .highPriorityGesture(
                TapGesture().modifiers(.command)
                    .onEnded {
                        browserVM.toggleGroupSelection(group.id)
                    }
                    .exclusively(
                        before: TapGesture().modifiers(.shift).onEnded {
                            browserVM.extendGroupSelection(to: group.id)
                        }
                    )
            )
            .dropDestination(for: String.self) { items, _ in
                guard let draggedTabID = draggedTabID(from: items) else { return false }
                return moveDraggedTab(draggedTabID, to: group.id)
            } isTargeted: { isTargeted in
                if isTargeted {
                    dropTargetGroupID = group.id
                } else if dropTargetGroupID == group.id {
                    dropTargetGroupID = nil
                }
            }
            .contextMenu {
                if isMultiSelected, browserVM.sidebarSelectionCount > 1 {
                    Button("Close \(browserVM.sidebarSelectionCount) Selected Items") {
                        browserVM.closeSidebarSelection()
                    }
                    Button("Clear Selection") {
                        browserVM.clearSidebarSelection()
                    }
                    Divider()
                }
                Button(targetGroupCount > 1 ? "Rename \(targetGroupCount) Folders" : "Rename Folder") {
                    beginRenaming(group, targetGroupIDs: targetGroupIDs)
                }
                Button(targetGroupCount > 1 ? "Ungroup Tabs in \(targetGroupCount) Folders" : "Ungroup Tabs") {
                    browserVM.ungroupTabs(in: targetGroupIDs)
                }
                .disabled(!selectedFoldersHaveTabs)
                Button(
                    targetGroupCount > 1 ? "Delete \(targetGroupCount) Folders" : "Delete Folder",
                    role: .destructive
                ) {
                    browserVM.deleteTabGroups(targetGroupIDs)
                }
            }

            if !group.isCollapsed {
                ForEach(tabs) { tab in
                    tabItem(tab, compact: false)
                        .transition(tabTransition)
                }
            }
        }
    }

    private func groupedTabs(for group: TabGroup) -> [Tab] {
        browserVM.tabs.filter {
            !$0.isFavorite && !$0.isPinned && $0.groupID == group.id
        }
    }

    private var renameFolderAlertTitle: String {
        groupIDsBeingRenamed.count > 1
            ? "Rename \(groupIDsBeingRenamed.count) Folders"
            : "Rename Folder"
    }

    private func contextMenuGroupIDs(for group: TabGroup) -> Set<UUID> {
        browserVM.selectedGroupIDs.contains(group.id)
            ? browserVM.selectedGroupIDs
            : [group.id]
    }

    private func beginRenaming(_ group: TabGroup, targetGroupIDs: Set<UUID>? = nil) {
        groupIDsBeingRenamed = targetGroupIDs ?? [group.id]
        pendingGroupTitle = groupIDsBeingRenamed.count == 1 ? group.title : ""
        isRenameGroupAlertPresented = true
    }

    private func beginRenaming(_ workspace: PersistedWorkspace) {
        workspaceIDBeingRenamed = workspace.id
        pendingWorkspaceName = workspace.name
        isRenameWorkspaceAlertPresented = true
    }

    private func beginCreatingWorkspace() {
        pendingNewWorkspaceName = browserVM.suggestedWorkspaceName()
        isCreateWorkspaceAlertPresented = true
    }

    private func draggedTabID(from items: [String]) -> UUID? {
        items.compactMap { UUID(uuidString: $0) }.first
    }

    private func moveDraggedTab(_ tabID: UUID, to groupID: UUID) -> Bool {
        guard let tab = browserVM.tabs.first(where: { $0.id == tabID }) else { return false }
        guard !tab.isPinned && !tab.isFavorite else { return false }
        guard tab.groupID != groupID else { return false }

        browserVM.moveTab(tabID, toGroup: groupID)
        performReorderHapticFeedback()
        return true
    }

    // MARK: - Tab Item with Drag-to-Reorder

    /// Plain click: activates the tab and clears any multi-selection.
    /// Cmd/Shift-clicks are recognized by the high-priority tap gestures in
    /// `selectionGestures(for:)`; the guard keeps a Button-action fallback
    /// from double-handling them.
    private func handleTabClick(_ tab: Tab) {
        let modifiers = NSEvent.modifierFlags
        guard !modifiers.contains(.command), !modifiers.contains(.shift) else { return }
        browserVM.selectTab(tab.id)
    }

    /// Cmd-click toggles the tab in/out of the selection; Shift-click extends
    /// the range. Attached as high-priority gestures because modified clicks
    /// must be recognized by the gesture system itself, ahead of the row's
    /// Button, to work reliably on macOS.
    private func selectionGestures(for tab: Tab) -> some Gesture {
        TapGesture().modifiers(.command)
            .onEnded {
                browserVM.toggleTabSelection(tab.id)
            }
            .exclusively(
                before: TapGesture().modifiers(.shift).onEnded {
                    browserVM.extendTabSelection(to: tab.id)
                }
            )
    }

    private func favoriteTabItem(_ tab: Tab) -> some View {
        FavoriteTabItemView(
            tab: tab,
            isActive: tab.id == browserVM.activeTabID,
            onSelect: {
                guard draggingTabID == nil else { return }
                handleTabClick(tab)
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
            onTogglePin: { browserVM.togglePin(tab.id) },
            onToggleFavorite: { browserVM.toggleFavorite(tab.id) },
            isMultiSelected: browserVM.selectedTabIDs.contains(tab.id)
        )
        .highPriorityGesture(selectionGestures(for: tab))
    }

    private func tabItem(_ tab: Tab, compact: Bool) -> some View {
        let isDragging = draggingTabID == tab.id
        let rowHeight = compact ? compactRowHeight : regularRowHeight

        return TabItemView(
            tab: tab,
            isActive: tab.id == browserVM.activeTabID,
            isMultiSelected: browserVM.selectedTabIDs.contains(tab.id),
            compact: compact,
            onSelect: {
                // Suppress selection while a drag is active to avoid
                // the Button firing on mouse-up at the end of a drag.
                guard draggingTabID == nil else { return }
                handleTabClick(tab)
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
            onTogglePin: { browserVM.togglePin(tab.id) },
            onToggleFavorite: { browserVM.toggleFavorite(tab.id) },
            tabGroups: browserVM.tabGroups,
            onCreateFolderFromTab: { browserVM.createTabGroup(containing: tab.id) },
            onMoveToGroup: { browserVM.moveTab(tab.id, toGroup: $0) },
            selectionCount: browserVM.sidebarSelectionCount,
            onCloseSelection: { browserVM.closeSidebarSelection() },
            onMoveSelectionToGroup: { browserVM.moveSelectedTabs(toGroup: $0) },
            onClearSelection: { browserVM.clearSidebarSelection() }
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
        .highPriorityGesture(selectionGestures(for: tab))
        .draggable(tab.id.uuidString)
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
        performReorderHapticFeedback()
        return true
    }

    private func performReorderHapticFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Two tabs belong to the same drag section when they share pinned state,
    /// folder membership, and, for ungrouped tabs, the same date grouping.
    private func sameDragSection(_ a: Tab, _ b: Tab) -> Bool {
        guard a.isPinned == b.isPinned else { return false }
        if a.isPinned { return true }
        guard a.groupID == b.groupID else { return false }
        if a.groupID != nil { return true }
        return Calendar.current.isDateInToday(a.lastAccessedAt)
            == Calendar.current.isDateInToday(b.lastAccessedAt)
    }
}
