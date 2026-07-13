import SwiftUI

extension PersistedWorkspace {
    var accentColor: Color {
        switch colorName {
        case "blue":
            return .blue
        case "green":
            return .green
        case "orange":
            return .orange
        case "pink":
            return .pink
        case "purple":
            return .purple
        case "teal":
            return .teal
        default:
            return BrowseColor.accent
        }
    }
}

/// Custom workspace switcher panel: every workspace is listed at once and each
/// row exposes its actions inline, so switching, renaming, deleting, and
/// creating never require reopening a menu.
struct WorkspaceSwitcherView: View {
    @Environment(BrowserViewModel.self) private var browserVM

    let onRename: (PersistedWorkspace) -> Void
    let onCreate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("WORKSPACES")
                .font(BrowseFont.badge)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 2)

            ForEach(browserVM.workspaces) { workspace in
                WorkspaceSwitcherRow(
                    workspace: workspace,
                    isActive: workspace.id == browserVM.activeWorkspaceID,
                    onSelect: {
                        browserVM.switchWorkspace(to: workspace.id)
                        onDismiss()
                    },
                    onRename: {
                        onDismiss()
                        onRename(workspace)
                    },
                    onDuplicate: {
                        browserVM.duplicateWorkspace(workspace.id)
                        onDismiss()
                    },
                    onDelete: {
                        browserVM.deleteWorkspace(workspace.id)
                    }
                )
            }

            Rectangle()
                .fill(BrowseColor.borderSubtle)
                .frame(height: 0.5)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)

            newWorkspaceRow
        }
        .padding(8)
        .frame(width: 236)
    }

    private var newWorkspaceRow: some View {
        Button {
            onDismiss()
            onCreate()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                Text("New Workspace")
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(height: 30)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(HoverHighlightButtonStyle())
    }
}

private struct WorkspaceSwitcherRow: View {
    let workspace: PersistedWorkspace
    let isActive: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                HStack(spacing: 7) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(workspace.accentColor.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(workspace.accentColor.opacity(0.30), lineWidth: 0.7)
                            )
                        Image(systemName: workspace.iconName ?? "square.grid.2x2")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(workspace.accentColor)
                    }
                    .frame(width: 22, height: 22)

                    Text(workspace.name)
                        .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    if isActive && !isHovering {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(workspace.accentColor)
                    }
                }
                .padding(.leading, 6)
                .padding(.trailing, isHovering ? 0 : 6)
                .frame(height: 30)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)

            if isHovering {
                rowActionButton(systemImage: "pencil", help: "Rename Workspace", action: onRename)
                rowActionButton(systemImage: "trash", help: "Delete Workspace", action: onDelete)
                    .disabled(workspace.isDefault)
                    .opacity(workspace.isDefault ? 0.35 : 1)
                    .padding(.trailing, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(rowBackground)
        )
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Rename") {
                onRename()
            }
            Button("Duplicate") {
                onDuplicate()
            }
            Button("Delete", role: .destructive) {
                onDelete()
            }
            .disabled(workspace.isDefault)
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var rowBackground: Color {
        if isHovering {
            return BrowseColor.surfaceHover
        }
        if isActive {
            return BrowseColor.surfaceActive
        }
        return .clear
    }

    private func rowActionButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Plain button style that paints a subtle rounded highlight while hovered.
private struct HoverHighlightButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovering ? BrowseColor.surfaceHover : Color.clear)
            )
            .onHover { isHovering = $0 }
    }
}
