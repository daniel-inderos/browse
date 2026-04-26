import SwiftUI
import MarkdownUI

struct ChatPaneView: View {
    @Bindable var viewModel: ChatViewModel
    var onWidthCommit: (CGFloat) -> Void
    var onClear: () -> Void
    var onClose: () -> Void

    @State private var sidebarWidth: CGFloat
    @State private var resizeStartWidth: CGFloat?
    @State private var isClearConfirmationPresented: Bool = false
    @FocusState private var isInputFocused: Bool

    private let minWidth: CGFloat = 300
    private let maxWidth: CGFloat = 560

    init(
        viewModel: ChatViewModel,
        initialWidth: CGFloat,
        onWidthCommit: @escaping (CGFloat) -> Void,
        onClear: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.viewModel = viewModel
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

            Text("Claude can read the page content and answer your questions.")
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
        HStack(spacing: 8) {
            TextField("Ask\u{2026}", text: $viewModel.inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .focused($isInputFocused)
                .onSubmit { submitMessage() }

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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(BrowseColor.borderSubtle)
                .frame(height: 0.5)
        }
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
