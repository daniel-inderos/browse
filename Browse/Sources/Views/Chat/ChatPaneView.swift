import SwiftUI
import AppKit
import MarkdownUI

struct ChatPaneView: View {
    @Bindable var viewModel: ChatViewModel
    var tabMentionCandidates: [ChatTabMentionCandidate]
    var onAttachTabMention: (ChatTabMentionCandidate) async -> Void
    var onWidthCommit: (CGFloat) -> Void
    var onClear: () -> Void
    var onClose: () -> Void

    @State private var sidebarWidth: CGFloat
    @State private var resizeStartWidth: CGFloat?
    @State private var isClearConfirmationPresented: Bool = false
    @State private var hoveredContextChipID: String?
    @State private var selectedMentionIndex: Int = 0
    @FocusState private var isInputFocused: Bool

    private let minWidth: CGFloat = 300
    private let maxWidth: CGFloat = 560

    init(
        viewModel: ChatViewModel,
        tabMentionCandidates: [ChatTabMentionCandidate],
        initialWidth: CGFloat,
        onAttachTabMention: @escaping (ChatTabMentionCandidate) async -> Void,
        onWidthCommit: @escaping (CGFloat) -> Void,
        onClear: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.tabMentionCandidates = tabMentionCandidates
        self.onAttachTabMention = onAttachTabMention
        self.onWidthCommit = onWidthCommit
        self.onClear = onClear
        self.onClose = onClose
        _sidebarWidth = State(initialValue: initialWidth)
    }

    var body: some View {
        paneContent
            .frame(width: sidebarWidth)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .leading) { sidebarResizeHandle }
            .onAppear {
                focusInputOnNextRunLoop()
            }
            .onDisappear {
                commitWidth()
            }
    }

    // MARK: - Pane Content

    private var paneContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            chatHeader
            chatMessages
            chatInputBar
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(BrowseColor.borderSubtle)
                .frame(width: 0.5)
        }
        .confirmationDialog(
            "Clear chat for this page?",
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Clear Chat", role: .destructive) {
                onClear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the current page’s chat history.")
        }
    }

    // MARK: - Header (draggable)

    private var chatHeader: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(BrowseColor.accent)
                    .frame(width: 6, height: 6)

                Text(viewModel.pageTitle.isEmpty ? "Chat" : viewModel.pageTitle)
                    .font(BrowseFont.briefingCaption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: { isClearConfirmationPresented = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.quaternary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.conversationHistory.isEmpty || viewModel.isStreaming)
            .help("Clear chat for this page")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.quaternary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.001))
    }

    // MARK: - Messages

    private var chatMessages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if viewModel.conversationHistory.isEmpty && !viewModel.isStreaming {
                        emptyState
                    }

                    ForEach(viewModel.conversationHistory) { message in
                        chatEntry(message)
                            .id(message.id)
                    }

                    if viewModel.isStreamingAnswer,
                       !viewModel.streamingResponse.isEmpty {
                        assistantEntry(viewModel.streamingResponse, isStreaming: true)
                            .id("streaming")
                    }

                    if viewModel.isStreaming && viewModel.streamingResponse.isEmpty {
                        thinkingIndicator
                            .id("thinking")
                    }

                    if let error = viewModel.errorMessage {
                        errorEntry(error)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onChange(of: viewModel.conversationHistory.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    if let lastID = viewModel.conversationHistory.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.streamingResponse) { _, _ in
                proxy.scrollTo("streaming", anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask about this page")
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundStyle(.secondary)

            Text("OpenAI can read the page content and answer your questions.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.quaternary)
                .lineSpacing(2)
        }
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Message entries (editorial, not bubbles)

    @ViewBuilder
    private func chatEntry(_ message: ConversationMessage) -> some View {
        if message.role == .user {
            userEntry(message.content)
        } else {
            assistantEntry(message.content, isStreaming: false)
        }
    }

    private func userEntry(_ content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(BrowseColor.accent.opacity(0.4))
                    .frame(width: 2, height: 14)

                Text("YOU")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.quaternary)
                    .padding(.leading, 8)
            }

            Text(content)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .lineSpacing(2)
        }
    }

    private func assistantEntry(_ content: String, isStreaming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Markdown(content)
                .markdownTheme(.chatCompact)

            if isStreaming {
                Circle()
                    .fill(BrowseColor.accent)
                    .frame(width: 5, height: 5)
                    .modifier(PulsingDot())
            }
        }
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(BrowseColor.accent)
                .frame(width: 5, height: 5)
                .modifier(PulsingDot())

            Text("Thinking\u{2026}")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.quaternary)
        }
    }

    private func errorEntry(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10))
                .foregroundStyle(.orange.opacity(0.7))

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Input Bar

    private var chatInputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !filteredTabMentionCandidates.isEmpty {
                tabMentionMenu
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if hasContextChips {
                contextChipRow
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 8) {
                ChatInputTextField(
                    placeholder: "Ask\u{2026}",
                    text: $viewModel.inputText,
                    isFocused: $isInputFocused,
                    onSubmit: submitMessage,
                    canNavigateMentions: { !filteredTabMentionCandidates.isEmpty },
                    onMoveMentionSelection: moveMentionSelection,
                    onAcceptMention: acceptSelectedTabMention
                )
                .frame(height: 24)

                if !viewModel.inputText.isEmpty {
                    Button(action: submitMessage) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(BrowseColor.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .disabled(viewModel.isStreaming)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(BrowseColor.borderSubtle)
                .frame(height: 0.5)
        }
        .onChange(of: activeTabMentionQuery) { _, _ in
            selectedMentionIndex = 0
        }
        .onChange(of: filteredTabMentionCandidates.map(\.id)) { _, _ in
            clampSelectedMentionIndex()
        }
    }

    private var contextChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let contextLabel = viewModel.pageContextLabel {
                    contextChip(
                        id: "page",
                        systemImage: "doc.text.magnifyingglass",
                        label: contextLabel,
                        accessibilityLabel: "Remove page context",
                        help: "Remove current page from model context",
                        action: viewModel.removePageContextFromModel
                    )
                }

                ForEach(viewModel.mentionedTabContexts) { context in
                    contextChip(
                        id: context.id.uuidString,
                        systemImage: "macwindow",
                        label: context.label,
                        accessibilityLabel: "Remove tagged tab",
                        help: "Remove tagged tab from model context",
                        action: {
                            viewModel.removeMentionedTabContext(id: context.id)
                        }
                    )
                }
            }
        }
    }

    private var tabMentionMenu: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(filteredTabMentionCandidates.enumerated()), id: \.element.id) { index, candidate in
                        let isSelected = index == clampedSelectedMentionIndex

                        Button {
                            selectTabMention(candidate)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: candidate.kind == .briefing ? "doc.richtext" : "macwindow")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(BrowseColor.accent)
                                    .frame(width: 16)

                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        Text(candidate.displayTitle)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .foregroundStyle(.primary.opacity(0.82))
                                            .lineLimit(1)

                                        if candidate.isActive {
                                            Text("Current")
                                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                                .foregroundStyle(BrowseColor.accent)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(BrowseColor.accent.opacity(0.10), in: Capsule())
                                        }
                                    }

                                    Text(candidate.displaySubtitle)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundStyle(.quaternary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 8)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? BrowseColor.surfaceActive : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(candidate.id)
                    }
                }
                .padding(3)
            }
            .frame(maxHeight: 220)
            .onChange(of: selectedTabMentionCandidate?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.96), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(BrowseColor.borderSubtle, lineWidth: 0.5)
        }
        .shadow(color: BrowseColor.shadowSubtle.opacity(0.8), radius: 8, x: 0, y: 3)
    }

    private var selectedTabMentionCandidate: ChatTabMentionCandidate? {
        let candidates = filteredTabMentionCandidates
        guard !candidates.isEmpty else { return nil }
        return candidates[clampedSelectedMentionIndex]
    }

    private var clampedSelectedMentionIndex: Int {
        let candidateCount = filteredTabMentionCandidates.count
        guard candidateCount > 0 else { return 0 }
        return max(0, min(selectedMentionIndex, candidateCount - 1))
    }

    private func moveMentionSelection(by delta: Int) {
        let candidateCount = filteredTabMentionCandidates.count
        guard candidateCount > 0 else { return }
        selectedMentionIndex = (clampedSelectedMentionIndex + delta + candidateCount) % candidateCount
    }

    private func acceptSelectedTabMention() {
        guard let candidate = selectedTabMentionCandidate else { return }
        selectTabMention(candidate)
    }

    private func clampSelectedMentionIndex() {
        selectedMentionIndex = clampedSelectedMentionIndex
    }

    private func contextChip(
        id: String,
        systemImage: String,
        label: String,
        accessibilityLabel: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BrowseColor.accent)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Button(action: action) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 16)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(hoveredContextChipID == id ? 1 : 0)
            .allowsHitTesting(hoveredContextChipID == id)
            .accessibilityLabel(accessibilityLabel)
            .help(help)
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(BrowseColor.surfaceSubtle, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(BrowseColor.borderSubtle, lineWidth: 0.5)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredContextChipID = hovering ? id : nil
            }
        }
        .animation(.easeOut(duration: 0.12), value: hoveredContextChipID)
    }

    private var hasContextChips: Bool {
        viewModel.pageContextLabel != nil || !viewModel.mentionedTabContexts.isEmpty
    }

    private var filteredTabMentionCandidates: [ChatTabMentionCandidate] {
        guard let query = activeTabMentionQuery else { return [] }

        let attachedIDs = Set(viewModel.mentionedTabContexts.map(\.id))
        let candidates = tabMentionCandidates.filter { !attachedIDs.contains($0.id) }
        let filtered = candidates.filter { candidate in
            guard !query.isEmpty else { return true }

            return candidate.displayTitle.localizedCaseInsensitiveContains(query)
                || candidate.displaySubtitle.localizedCaseInsensitiveContains(query)
        }

        return filtered
    }

    private var activeTabMentionQuery: String? {
        let text = viewModel.inputText
        guard !text.isEmpty else { return nil }

        let tokenStart = text.lastIndex(where: { $0.isWhitespace })
            .map { text.index(after: $0) } ?? text.startIndex
        guard tokenStart < text.endIndex else { return nil }

        let token = text[tokenStart...]
        guard token.first == "@" else { return nil }

        return String(token.dropFirst())
    }

    private func selectTabMention(_ candidate: ChatTabMentionCandidate) {
        replaceActiveMentionToken(with: candidate.mentionText)
        Task {
            await onAttachTabMention(candidate)
        }
    }

    private func replaceActiveMentionToken(with mentionText: String) {
        let text = viewModel.inputText
        let tokenStart = text.lastIndex(where: { $0.isWhitespace })
            .map { text.index(after: $0) } ?? text.startIndex
        let prefix = text[..<tokenStart]
        viewModel.inputText = "\(prefix)\(mentionText) "
    }

    private func submitMessage() {
        let question = viewModel.inputText
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        viewModel.inputText = ""
        Task {
            await viewModel.sendMessage(question)
        }
    }

    private func focusInputOnNextRunLoop() {
        DispatchQueue.main.async {
            isInputFocused = true
        }
    }

    // MARK: - Width Resize

    private var sidebarResizeHandle: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.001))
            .frame(width: 8)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if resizeStartWidth == nil {
                            resizeStartWidth = sidebarWidth
                        }

                        if let resizeStartWidth {
                            sidebarWidth = clamp(
                                resizeStartWidth - value.translation.width,
                                min: minWidth,
                                max: maxWidth
                            )
                        }
                    }
                    .onEnded { _ in
                        resizeStartWidth = nil
                        commitWidth()
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private func commitWidth() {
        onWidthCommit(sidebarWidth)
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }
}

private struct ChatInputTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let canNavigateMentions: () -> Bool
    let onMoveMentionSelection: (Int) -> Void
    let onAcceptMention: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isFocused: isFocused,
            onSubmit: onSubmit,
            canNavigateMentions: canNavigateMentions,
            onMoveMentionSelection: onMoveMentionSelection,
            onAcceptMention: onAcceptMention
        )
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.delegate = context.coordinator
        context.coordinator.textField = textField
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = isFocused
        context.coordinator.onSubmit = onSubmit
        context.coordinator.canNavigateMentions = canNavigateMentions
        context.coordinator.onMoveMentionSelection = onMoveMentionSelection
        context.coordinator.onAcceptMention = onAcceptMention
        textField.isEnabled = isEnabled

        if textField.stringValue != text {
            textField.stringValue = text
        }

        guard isFocused.wrappedValue, let window = textField.window else { return }
        if window.firstResponder !== textField.currentEditor() {
            window.makeFirstResponder(textField)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var isFocused: FocusState<Bool>.Binding
        var onSubmit: () -> Void
        var canNavigateMentions: () -> Bool
        var onMoveMentionSelection: (Int) -> Void
        var onAcceptMention: () -> Void
        weak var textField: NSTextField?

        init(
            text: Binding<String>,
            isFocused: FocusState<Bool>.Binding,
            onSubmit: @escaping () -> Void,
            canNavigateMentions: @escaping () -> Bool,
            onMoveMentionSelection: @escaping (Int) -> Void,
            onAcceptMention: @escaping () -> Void
        ) {
            self.text = text
            self.isFocused = isFocused
            self.onSubmit = onSubmit
            self.canNavigateMentions = canNavigateMentions
            self.onMoveMentionSelection = onMoveMentionSelection
            self.onAcceptMention = onAcceptMention
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

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                guard canNavigateMentions() else { return false }
                onMoveMentionSelection(1)
                return true

            case #selector(NSResponder.moveUp(_:)):
                guard canNavigateMentions() else { return false }
                onMoveMentionSelection(-1)
                return true

            case #selector(NSResponder.insertNewline(_:)):
                if canNavigateMentions() {
                    onAcceptMention()
                } else {
                    onSubmit()
                }
                return true

            default:
                return false
            }
        }
    }
}

// MARK: - Compact Chat Markdown Theme

@MainActor
extension MarkdownUI.Theme {
    static let chatCompact = Theme()
        .text {
            FontSize(13.5)
            ForegroundColor(.primary.opacity(0.82))
        }
        .link {
            ForegroundColor(BrowseColor.accent)
        }
        .strong {
            FontWeight(.semibold)
        }
        .code {
            FontSize(12)
            FontFamilyVariant(.monospaced)
            BackgroundColor(Color.primary.opacity(0.04))
        }
        .paragraph { configuration in
            configuration.label
                .lineSpacing(3)
                .markdownMargin(top: 0, bottom: 8)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 2, bottom: 2)
        }
}
