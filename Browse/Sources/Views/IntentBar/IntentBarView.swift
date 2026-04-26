import SwiftUI
import AppKit

struct IntentBarView: View {
    @Environment(BrowserViewModel.self) private var browserVM
    let onFocusChange: (Bool) -> Void
    @State private var viewModel = IntentBarViewModel()
    @FocusState private var isFocused: Bool
    @State private var isHoveringBar = false
    @State private var pendingAutoHideTask: Task<Void, Never>?
    @State private var keyEventMonitor: Any?
    @State private var selectedSuggestionID: String?

    init(onFocusChange: @escaping (Bool) -> Void = { _ in }) {
        self.onFocusChange = onFocusChange
    }

    var body: some View {
        HStack(spacing: 8) {
            // Navigation buttons (when showing a web tab)
            if let webVM = browserVM.activeTab?.webTabViewModel {
                navigationButtons(webVM)
            }

            // Input field
            inputField

            // Intent badge
            IntentBadge(classification: viewModel.liveClassification)
                .animation(.spring(duration: 0.25, bounce: 0.2), value: viewModel.liveClassification?.label)

            // Clear button
            if !viewModel.text.isEmpty {
                Button(action: {
                    viewModel.text = ""
                    isFocused = true
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.quaternary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            // Chat with page button
            if browserVM.activeTab?.kind == .web,
               browserVM.activeTab?.webTabViewModel?.currentURL != nil {
                Button(action: { browserVM.toggleChatPane() }) {
                    Image(systemName: browserVM.isChatPaneVisible
                          ? "bubble.left.and.text.bubble.right.fill"
                          : "bubble.left.and.text.bubble.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(browserVM.isChatPaneVisible
                                         ? BrowseColor.accent
                                         : Color.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Chat with page (\u{2318}J)")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(intentBarBackground)
        .overlay(intentBarBorder)
        .overlay(alignment: .topLeading) {
            if shouldShowSuggestions {
                IntentBarSuggestions(
                    sections: suggestionSections,
                    highlightedSuggestionID: selectedSuggestionID,
                    onSelect: applySuggestion
                )
                .padding(.horizontal, 12)
                .padding(.top, 42)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .zIndex(2)
        .animation(.easeOut(duration: 0.2), value: isFocused)
        .animation(.easeOut(duration: 0.15), value: isHoveringBar)
        .animation(.easeOut(duration: 0.15), value: suggestionSections)
        .onAppear {
            installKeyEventMonitor()
            onFocusChange(isFocused)
        }
        .onHover { hovering in
            isHoveringBar = hovering
            if hovering {
                pendingAutoHideTask?.cancel()
                pendingAutoHideTask = nil
            } else {
                pendingAutoHideTask?.cancel()
                // Give the pointer a brief grace window to move from the top reveal
                // strip into the bar without triggering an immediate collapse.
                pendingAutoHideTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(320))
                    guard !Task.isCancelled else { return }
                    guard !isFocused else { return }
                    browserVM.hideIntentBarIfReadingPositionActive()
                }
            }
        }
        .onDisappear {
            pendingAutoHideTask?.cancel()
            pendingAutoHideTask = nil
            removeKeyEventMonitor()
            onFocusChange(false)
        }
        .onChange(of: isFocused) { _, focused in
            onFocusChange(focused)
        }
        .onChange(of: browserVM.isIntentBarFocused) { _, focused in
            if focused {
                isFocused = true
                selectedSuggestionID = nil
                selectAllIntentBarTextOnNextRunLoop()
                if let webVM = browserVM.activeTab?.webTabViewModel, let url = webVM.currentURL {
                    viewModel.setURLDisplay(url)
                } else {
                    viewModel.text = ""
                }
                browserVM.isIntentBarFocused = false
            }
        }
        .onChange(of: viewModel.text) { _, _ in
            selectedSuggestionID = nil
        }
        .onChange(of: suggestionSections) { _, sections in
            let availableIDs = Set(sections.flatMap(\.suggestions).map(\.id))
            guard let currentSuggestionID = selectedSuggestionID else { return }
            if !availableIDs.contains(currentSuggestionID) {
                selectedSuggestionID = nil
            }
        }
        .onChange(of: browserVM.activeTab?.webTabViewModel?.currentURL) { _, url in
            if !isFocused, let url {
                viewModel.text = url.absoluteString
            }
        }
    }

    private func selectAllIntentBarText() {
        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
    }

    private func selectAllIntentBarTextOnNextRunLoop() {
        DispatchQueue.main.async {
            // Let AppKit finish installing the field editor before selecting.
            selectAllIntentBarText()
        }
    }

    private var shouldShowSuggestions: Bool {
        isFocused && !suggestionSections.isEmpty
    }

    private var inputField: some View {
        SelectAllOnClickTextField(
            placeholder: "Search, ask a question, or enter a URL…",
            text: $viewModel.text,
            isFocused: $isFocused,
            onSubmit: submitIntentBarText
        )
        .frame(maxWidth: .infinity)
        .layoutPriority(1)
    }

    private var flattenedSuggestions: [IntentSuggestion] {
        suggestionSections.flatMap(\.suggestions)
    }

    private var selectedSuggestion: IntentSuggestion? {
        guard let selectedSuggestionID else { return nil }
        return flattenedSuggestions.first(where: { $0.id == selectedSuggestionID })
    }

    private var suggestionSections: [IntentSuggestionSection] {
        let query = normalizedQuery(viewModel.text)
        guard !query.isEmpty else { return [] }

        let recentBriefings = recentBriefingSuggestions(matching: query)
        let openTabs = openTabSuggestions(matching: query)
        let frequentDomains = frequentDomainSuggestions(matching: query)

        var sections: [IntentSuggestionSection] = []
        if !recentBriefings.isEmpty {
            sections.append(IntentSuggestionSection(title: "Recent Briefings", suggestions: recentBriefings))
        }
        if !openTabs.isEmpty {
            sections.append(IntentSuggestionSection(title: "Open Tabs", suggestions: openTabs))
        }
        if !frequentDomains.isEmpty {
            sections.append(IntentSuggestionSection(title: "Frequent Domains", suggestions: frequentDomains))
        }
        return sections
    }

    private func recentBriefingSuggestions(matching query: String) -> [IntentSuggestion] {
        var seen = Set<String>()
        var results: [IntentSuggestion] = []

        for tab in browserVM.tabs
            .filter({ $0.kind == .briefing })
            .sorted(by: { $0.lastAccessedAt > $1.lastAccessedAt }) {
            let candidate = tab.briefingViewModel?.document.query ?? tab.title
            let cleaned = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            guard cleaned.localizedCaseInsensitiveContains(query) else { continue }
            let dedupeKey = cleaned.lowercased()
            guard !seen.contains(dedupeKey) else { continue }
            seen.insert(dedupeKey)
            results.append(
                IntentSuggestion(
                    kind: .briefingQuery,
                    title: cleaned,
                    subtitle: "Generate a briefing",
                    fillText: cleaned
                )
            )
            if results.count >= 4 { break }
        }

        return results
    }

    private func openTabSuggestions(matching query: String) -> [IntentSuggestion] {
        var seen = Set<String>()
        var results: [IntentSuggestion] = []

        for tab in browserVM.tabs
            .filter({ $0.kind == .web })
            .sorted(by: { $0.lastAccessedAt > $1.lastAccessedAt }) {
            let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            guard title.localizedCaseInsensitiveContains(query) else { continue }
            let dedupeKey = title.lowercased()
            guard !seen.contains(dedupeKey) else { continue }
            seen.insert(dedupeKey)

            let host = tab.url?.displayHost ?? tab.webTabViewModel?.currentURL?.displayHost
            results.append(
                IntentSuggestion(
                    kind: .openTab,
                    title: title,
                    subtitle: host,
                    fillText: title,
                    tabID: tab.id
                )
            )
            if results.count >= 5 { break }
        }

        return results
    }

    private func frequentDomainSuggestions(matching query: String) -> [IntentSuggestion] {
        struct DomainStats {
            var count: Int
            var lastAccessedAt: Date
        }

        var domains: [String: DomainStats] = [:]
        for tab in browserVM.tabs where tab.kind == .web {
            guard let host = (tab.url ?? tab.webTabViewModel?.currentURL)?.host?.lowercased() else { continue }
            let existing = domains[host]
            domains[host] = DomainStats(
                count: (existing?.count ?? 0) + 1,
                lastAccessedAt: max(existing?.lastAccessedAt ?? .distantPast, tab.lastAccessedAt)
            )
        }

        return domains
            .filter { host, _ in host.localizedCaseInsensitiveContains(query) }
            .sorted { lhs, rhs in
                if lhs.value.count != rhs.value.count {
                    return lhs.value.count > rhs.value.count
                }
                return lhs.value.lastAccessedAt > rhs.value.lastAccessedAt
            }
            .prefix(5)
            .map { host, stats in
                IntentSuggestion(
                    kind: .frequentDomain,
                    title: host,
                    subtitle: stats.count == 1 ? "Visited once" : "Visited \(stats.count)x",
                    fillText: "https://\(host)"
                )
            }
    }

    private func normalizedQuery(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applySuggestion(_ suggestion: IntentSuggestion) {
        if suggestion.kind == .openTab, let tabID = suggestion.tabID {
            browserVM.selectTab(tabID)
            isFocused = false
            selectedSuggestionID = nil
            return
        }

        viewModel.text = suggestion.fillText
        let intent = viewModel.submit()
        browserVM.handleIntent(intent)
        isFocused = false
        selectedSuggestionID = nil
    }

    private func submitIntentBarText() {
        if let suggestion = selectedSuggestion {
            applySuggestion(suggestion)
            return
        }
        guard !viewModel.text.isEmpty else { return }
        let intent = viewModel.submit()
        browserVM.handleIntent(intent)
        // Let URL updates reflect immediately after navigation starts.
        isFocused = false
    }

    private func installKeyEventMonitor() {
        guard keyEventMonitor == nil else { return }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
        }
    }

    private func removeKeyEventMonitor() {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard isFocused else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let blockedFlags: NSEvent.ModifierFlags = [.command, .control, .option]
        guard flags.intersection(blockedFlags).isEmpty else { return event }

        switch event.keyCode {
        case 125: // down
            guard shouldShowSuggestions else { return event }
            moveSelection(step: 1)
            return nil
        case 126: // up
            guard shouldShowSuggestions else { return event }
            moveSelection(step: -1)
            return nil
        case 36, 76: // return / keypad enter
            guard let selectedSuggestion else { return event }
            applySuggestion(selectedSuggestion)
            return nil
        case 53: // escape
            guard selectedSuggestionID != nil else { return event }
            selectedSuggestionID = nil
            return nil
        default:
            return event
        }
    }

    private func moveSelection(step: Int) {
        let suggestions = flattenedSuggestions
        guard !suggestions.isEmpty else { return }

        guard let currentSelectedSuggestionID = selectedSuggestionID,
              let currentIndex = suggestions.firstIndex(where: { $0.id == currentSelectedSuggestionID }) else {
            selectedSuggestionID = (step > 0 ? suggestions.first : suggestions.last)?.id
            return
        }

        let nextIndex = (currentIndex + step + suggestions.count) % suggestions.count
        selectedSuggestionID = suggestions[nextIndex].id
    }

    // MARK: - Navigation Buttons

    private func navigationButtons(_ webVM: WebTabViewModel) -> some View {
        HStack(spacing: 2) {
            navButton(icon: "chevron.left", enabled: webVM.canGoBack) { webVM.goBack() }
            navButton(icon: "chevron.right", enabled: webVM.canGoForward) { webVM.goForward() }

            if webVM.isLoading {
                navButton(icon: "xmark", enabled: true) { webVM.stopLoading() }
            } else {
                navButton(icon: "arrow.clockwise", enabled: true) { webVM.reload() }
            }
        }
        .padding(.leading, 2)
    }

    private func navButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(enabled ? .secondary : .quaternary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Bar Styling

    private var intentBarBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.ultraThinMaterial)
            .shadow(
                color: isFocused ? BrowseColor.shadowWarm : BrowseColor.shadowSubtle,
                radius: isFocused ? 12 : 4,
                x: 0,
                y: isFocused ? 3 : 1
            )
    }

    private var intentBarBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(
                isFocused
                    ? BrowseColor.borderFocused
                    : (isHoveringBar ? BrowseColor.borderSubtle : Color.clear),
                lineWidth: isFocused ? 1.5 : 1
            )
    }
}

private struct SelectAllOnClickTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: isFocused, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> SelectingTextField {
        let textField = SelectingTextField()
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 14)
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.submit)
        context.coordinator.textField = textField
        return textField
    }

    func updateNSView(_ textField: SelectingTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = isFocused
        context.coordinator.onSubmit = onSubmit

        if textField.stringValue != text {
            textField.stringValue = text
        }

        guard isFocused.wrappedValue else { return }
        if textField.window?.firstResponder !== textField.currentEditor() {
            textField.window?.makeFirstResponder(textField)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var isFocused: FocusState<Bool>.Binding
        var onSubmit: () -> Void
        weak var textField: SelectingTextField?

        init(text: Binding<String>, isFocused: FocusState<Bool>.Binding, onSubmit: @escaping () -> Void) {
            self.text = text
            self.isFocused = isFocused
            self.onSubmit = onSubmit
        }

        @objc func submit() {
            onSubmit()
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isFocused.wrappedValue = true
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField else { return }
            text.wrappedValue = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isFocused.wrappedValue = false
        }
    }

    final class SelectingTextField: NSTextField {
        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            currentEditor()?.selectAll(nil)
        }
    }
}
