import SwiftUI

struct DownloadsPanelView: View {
    let manager: DownloadManager
    let activeWorkspaceID: UUID
    let workspaces: [PersistedWorkspace]
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if manager.downloads.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(manager.downloads) { item in
                            DownloadRowView(
                                item: item,
                                manager: manager,
                                workspaceName: DownloadWorkspaceNameResolver.name(
                                    for: item.workspaceID,
                                    activeWorkspaceID: activeWorkspaceID,
                                    workspaces: workspaces
                                )
                            )

                            if item.id != manager.downloads.last?.id {
                                Divider()
                                    .padding(.leading, 50)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.98))
                .shadow(color: BrowseColor.shadowSubtle.opacity(0.9), radius: 18, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(BrowseColor.borderSubtle, lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Downloads")
                .font(.system(size: 13, weight: .semibold))

            if manager.activeCount > 0 {
                Text("\(manager.activeCount)")
                    .font(BrowseFont.badge)
                    .foregroundStyle(.white)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Circle().fill(BrowseColor.accent))
            }

            Spacer()

            Button("Clear Completed") {
                manager.clearCompleted()
            }
            .font(.system(size: 11, weight: .medium))
            .disabled(!manager.hasCompletedDownloads)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close Downloads")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.secondary)

            Text("No downloads")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

private struct DownloadRowView: View {
    let item: DownloadItem
    let manager: DownloadManager
    let workspaceName: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            stateIcon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.filename)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)

                    if let sourceHost = item.sourceURL?.displayHost {
                        Text(sourceHost)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    if let workspaceName {
                        Text(workspaceName)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                if item.state == .waiting || item.state == .downloading {
                    ProgressView(value: item.progress)
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var actions: some View {
        switch item.state {
        case .completed:
            HStack(spacing: 4) {
                iconButton("arrow.up.forward.app", help: "Open") {
                    manager.open(item)
                }
                iconButton("folder", help: "Reveal in Finder") {
                    manager.revealInFinder(item)
                }
            }

        case .failed:
            if item.isRetryAvailable {
                iconButton("arrow.clockwise", help: "Retry") {
                    manager.retry(item)
                }
            }

        case .waiting, .downloading:
            EmptyView()
        }
    }

    private var stateIcon: some View {
        ZStack {
            Circle()
                .fill(iconBackground)

            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconForeground)
        }
    }

    private var iconName: String {
        switch item.state {
        case .waiting, .downloading:
            return "arrow.down"
        case .completed:
            return "checkmark"
        case .failed:
            return "exclamationmark"
        }
    }

    private var iconBackground: Color {
        switch item.state {
        case .waiting, .downloading:
            return BrowseColor.accent.opacity(0.12)
        case .completed:
            return BrowseColor.success.opacity(0.14)
        case .failed:
            return BrowseColor.destructive.opacity(0.14)
        }
    }

    private var iconForeground: Color {
        switch item.state {
        case .waiting, .downloading:
            return BrowseColor.accent
        case .completed:
            return BrowseColor.success
        case .failed:
            return BrowseColor.destructive
        }
    }

    private var statusText: String {
        switch item.state {
        case .waiting:
            return "Waiting"
        case .downloading:
            return "\(Int((item.progress * 100).rounded()))%"
        case .completed:
            return "Completed"
        case .failed:
            return item.errorSummary ?? "Failed"
        }
    }

    private var statusColor: Color {
        switch item.state {
        case .failed:
            return BrowseColor.destructive
        default:
            return .secondary
        }
    }

    private func iconButton(
        _ systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

struct DownloadWorkspaceNameResolver {
    static func name(
        for workspaceID: UUID?,
        activeWorkspaceID: UUID,
        workspaces: [PersistedWorkspace]
    ) -> String? {
        guard let workspaceID, workspaceID != activeWorkspaceID else { return nil }
        return workspaces.first { $0.id == workspaceID }?.name
    }
}
