import AppKit
import SwiftUI

struct HistoryPanelView: View {
    @Environment(BrowserViewModel.self) private var browserVM
    @State private var query = ""
    @State private var isConfirmingClear = false
    @FocusState private var isSearchFocused: Bool

    private var matchingEntries: [BrowsingHistoryEntry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return browserVM.browsingHistory }

        return browserVM.browsingHistory.filter { entry in
            entry.title.localizedStandardContains(normalizedQuery)
                || entry.url.absoluteString.localizedStandardContains(normalizedQuery)
                || entry.url.displayHost.localizedStandardContains(normalizedQuery)
        }
    }

    private var sections: [HistoryDaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: matchingEntries) {
            calendar.startOfDay(for: $0.visitedAt)
        }
        return grouped.keys.sorted(by: >).map { day in
            HistoryDaySection(day: day, entries: grouped[day] ?? [])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            searchField

            Divider()

            if browserVM.browsingHistory.isEmpty {
                emptyState(
                    icon: "clock.arrow.circlepath",
                    title: "No history yet",
                    detail: "Pages you visit will appear here."
                )
            } else if matchingEntries.isEmpty {
                emptyState(
                    icon: "magnifyingglass",
                    title: "No results",
                    detail: "Try searching for a page title or website."
                )
            } else {
                historyList
            }
        }
        .frame(width: 420, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            browserVM.refreshBrowsingHistory()
            isSearchFocused = true
        }
        .onExitCommand {
            browserVM.hideHistoryPanel()
        }
        .confirmationDialog(
            "Clear all browsing history?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                browserVM.clearBrowsingHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the list of pages you have visited. Open tabs and favorites will not be affected.")
        }
    }

    private var panelHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("History")
                    .font(.system(size: 16, weight: .semibold))
                Text("Recent visits across your tabs")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Clear") {
                isConfirmingClear = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(BrowseColor.destructive)
            .disabled(browserVM.browsingHistory.isEmpty)

            Button {
                browserVM.hideHistoryPanel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.055)))
            }
            .buttonStyle(.plain)
            .help("Close History")
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField("Search history", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFocused)
                .onSubmit {
                    if let firstEntry = matchingEntries.first {
                        browserVM.openHistoryEntry(firstEntry)
                    }
                }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear Search")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSearchFocused ? BrowseColor.borderFocused : BrowseColor.borderSubtle,
                    lineWidth: isSearchFocused ? 1 : 0.5
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 13)
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            HistoryEntryRow(entry: entry)
                        }
                    } header: {
                        sectionHeader(for: section.day)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
    }

    private func sectionHeader(for day: Date) -> some View {
        Text(dayTitle(day))
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 13)
            .padding(.bottom, 6)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.system(size: 14, weight: .semibold))

            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

private struct HistoryDaySection: Identifiable {
    let day: Date
    let entries: [BrowsingHistoryEntry]

    var id: Date { day }
}

private struct HistoryEntryRow: View {
    @Environment(BrowserViewModel.self) private var browserVM
    let entry: BrowsingHistoryEntry
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                browserVM.openHistoryEntry(entry)
            } label: {
                HStack(spacing: 10) {
                    FaviconView(url: entry.url, size: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(.primary)

                        Text(entry.url.displayString)
                            .font(.system(size: 10.5))
                            .lineLimit(1)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 10)

                    Text(entry.visitedAt.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(entry.title), \(entry.url.displayHost)")
            .contextMenu {
                Button("Open") {
                    browserVM.openHistoryEntry(entry)
                }
                Button("Open in New Tab") {
                    browserVM.openHistoryEntryInNewTab(entry)
                }
                Button("Copy Link") {
                    copyLink()
                }
                Divider()
                Button("Remove from History", role: .destructive) {
                    browserVM.removeHistoryEntry(entry)
                }
            }

            if isHovering {
                Button {
                    browserVM.removeHistoryEntry(entry)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Remove from History")
                .transition(.opacity)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, isHovering ? 4 : 10)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? BrowseColor.surfaceHover : Color.clear)
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private func copyLink() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.url.absoluteString, forType: .string)
    }
}
