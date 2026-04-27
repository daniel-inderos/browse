import SwiftUI

struct TabItemView: View {
    let tab: Tab
    let isActive: Bool
    let compact: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onCloseOthers: () -> Void
    let onCloseTabsBelow: () -> Void
    let onCopyURL: () -> Void
    let onDuplicate: () -> Void
    let onTogglePin: () -> Void
    let onToggleFavorite: () -> Void
    let tabGroups: [TabGroup]
    let onCreateFolderFromTab: () -> Void
    let onMoveToGroup: (UUID?) -> Void

    @State private var isHovering = false

    init(
        tab: Tab,
        isActive: Bool,
        compact: Bool = false,
        onSelect: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onCloseOthers: @escaping () -> Void,
        onCloseTabsBelow: @escaping () -> Void,
        onCopyURL: @escaping () -> Void,
        onDuplicate: @escaping () -> Void,
        onTogglePin: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void,
        tabGroups: [TabGroup],
        onCreateFolderFromTab: @escaping () -> Void,
        onMoveToGroup: @escaping (UUID?) -> Void
    ) {
        self.tab = tab
        self.isActive = isActive
        self.compact = compact
        self.onSelect = onSelect
        self.onClose = onClose
        self.onCloseOthers = onCloseOthers
        self.onCloseTabsBelow = onCloseTabsBelow
        self.onCopyURL = onCopyURL
        self.onDuplicate = onDuplicate
        self.onTogglePin = onTogglePin
        self.onToggleFavorite = onToggleFavorite
        self.tabGroups = tabGroups
        self.onCreateFolderFromTab = onCreateFolderFromTab
        self.onMoveToGroup = onMoveToGroup
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: compact ? 5 : 7) {
                // Icon
                Group {
                    if tab.kind == .briefing {
                        Image(systemName: "sparkles")
                            .font(.system(size: compact ? 9 : 10, weight: .semibold))
                            .foregroundStyle(BrowseColor.briefBadge)
                    } else {
                        FaviconView(url: tab.faviconURL ?? tab.url, size: compact ? 12 : 14)
                    }
                }
                .frame(width: compact ? 12 : 14, height: compact ? 12 : 14)
                .opacity(max(0.5, tab.decayOpacity))
                .saturation(tab.isStale && !tab.isPinned ? 0.3 : 1.0)

                // Title
                Text(displayTitle)
                    .font(compact ? .system(size: 11, weight: .medium) : BrowseFont.tabTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .opacity(tab.decayOpacity)

                // Close button — visible on hover or when active
                closeButton
            }
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 5 : 7)
            .frame(maxWidth: .infinity)
            .background(tabBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isActive ? BrowseColor.accent.opacity(0.15) : Color.clear,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Close") {
                onClose()
            }
            Button("Close Others") {
                onCloseOthers()
            }
            Button("Close Tabs Below") {
                onCloseTabsBelow()
            }
            Button("Copy URL") {
                onCopyURL()
            }
            .disabled(tab.webTabViewModel?.currentURL == nil && tab.url == nil)
            Button(tab.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                onToggleFavorite()
            }
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") {
                onTogglePin()
            }
            Button("Duplicate") {
                onDuplicate()
            }
            if !tab.isPinned {
                Divider()
                tabGroupMenu
            }
        }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.easeOut(duration: 0.15), value: isActive)
    }

    // MARK: - Helpers

    private var displayTitle: String {
        if compact {
            return String(tab.title.prefix(18))
        }
        return tab.title
    }

    private var tabBackground: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(BrowseColor.surfaceActive)
        } else if isHovering {
            return AnyShapeStyle(BrowseColor.surfaceHover)
        } else if compact && tab.isPinned {
            return AnyShapeStyle(BrowseColor.accent.opacity(0.06))
        } else {
            return AnyShapeStyle(Color.clear)
        }
    }

    @ViewBuilder
    private var tabGroupMenu: some View {
        Button("New Folder from Tab") {
            onCreateFolderFromTab()
        }

        if !tabGroups.isEmpty {
            Menu("Move to Folder") {
                Button("No Folder") {
                    onMoveToGroup(nil)
                }
                .disabled(tab.groupID == nil)

                ForEach(tabGroups) { group in
                    Button(group.title) {
                        onMoveToGroup(group.id)
                    }
                    .disabled(tab.groupID == group.id)
                }
            }
        }
    }

    @ViewBuilder
    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 16, height: 16)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .opacity(isHovering || isActive ? 1 : 0)
        .allowsHitTesting(isHovering || isActive)
        .accessibilityHidden(!(isHovering || isActive))
    }
}

struct FavoriteTabItemView: View {
    let tab: Tab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onCloseOthers: () -> Void
    let onCloseTabsBelow: () -> Void
    let onCopyURL: () -> Void
    let onDuplicate: () -> Void
    let onTogglePin: () -> Void
    let onToggleFavorite: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tabBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(tabBorder, lineWidth: 0.5)
                    )

                Group {
                    if tab.kind == .briefing {
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(BrowseColor.briefBadge)
                    } else {
                        FaviconView(url: tab.faviconURL ?? tab.url, size: 22)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(tab.title)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Close") {
                onClose()
            }
            Button("Close Others") {
                onCloseOthers()
            }
            Button("Close Tabs Below") {
                onCloseTabsBelow()
            }
            Button("Copy URL") {
                onCopyURL()
            }
            .disabled(tab.webTabViewModel?.currentURL == nil && tab.url == nil)
            Button("Remove from Favorites") {
                onToggleFavorite()
            }
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") {
                onTogglePin()
            }
            Button("Duplicate") {
                onDuplicate()
            }
        }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.easeOut(duration: 0.15), value: isActive)
    }

    private var tabBackground: Color {
        if isActive {
            return BrowseColor.surfaceActive
        }
        if isHovering {
            return BrowseColor.surfaceHover
        }
        return Color.primary.opacity(0.045)
    }

    private var tabBorder: Color {
        if isActive {
            return BrowseColor.accent.opacity(0.22)
        }
        return Color.primary.opacity(isHovering ? 0.10 : 0.07)
    }
}
