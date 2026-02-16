import SwiftUI
import MarkdownUI

struct ChatPaneView: View {
    @Bindable var viewModel: ChatViewModel
    var onGeometryCommit: (CGSize, CGFloat, CGFloat) -> Void
    var onClear: () -> Void
    var onClose: () -> Void

    private enum ResizeCorner: CaseIterable {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing

        var alignment: Alignment {
            switch self {
            case .topLeading:
                .topLeading
            case .topTrailing:
                .topTrailing
            case .bottomLeading:
                .bottomLeading
            case .bottomTrailing:
                .bottomTrailing
            }
        }
    }

    /// Accumulated offset from the default bottom-trailing anchor.
    @State private var offset: CGSize
    @State private var dragStartOffset: CGSize?
    @State private var dragStartLocation: CGPoint?

    @State private var paneWidth: CGFloat
    @State private var paneHeight: CGFloat
    @State private var activeResizeCorner: ResizeCorner?
    @State private var resizeStartOffset: CGSize?
    @State private var resizeStartWidth: CGFloat?
    @State private var resizeStartHeight: CGFloat?
    @State private var resizeStartLocation: CGPoint?
    @State private var isClearConfirmationPresented: Bool = false

    private let minWidth: CGFloat = 300
    private let maxWidth: CGFloat = 560
    private let minHeight: CGFloat = 280
    private let maxHeight: CGFloat = 720

    init(
        viewModel: ChatViewModel,
        initialOffset: CGSize,
        initialWidth: CGFloat,
        initialHeight: CGFloat,
        onGeometryCommit: @escaping (CGSize, CGFloat, CGFloat) -> Void,
        onClear: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onGeometryCommit = onGeometryCommit
        self.onClear = onClear
        self.onClose = onClose
        _offset = State(initialValue: initialOffset)
        _paneWidth = State(initialValue: initialWidth)
        _paneHeight = State(initialValue: initialHeight)
    }

    var body: some View {
        paneContent
            .frame(width: paneWidth, height: paneHeight)
            .offset(x: offset.width, y: offset.height)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .onDisappear {
                commitGeometry()
            }
    }

    // MARK: - Pane Content

    private var paneContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            chatHeader
            chatMessages
            chatInputBar
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(BrowseColor.borderSubtle, lineWidth: 0.5)
        )
        .shadow(color: BrowseColor.shadowWarm.opacity(0.7), radius: 20, x: 0, y: 8)
        .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
        .overlay(alignment: .topLeading) { resizeHandle(for: .topLeading) }
        .overlay(alignment: .topTrailing) { resizeHandle(for: .topTrailing) }
        .overlay(alignment: .bottomLeading) { resizeHandle(for: .bottomLeading) }
        .overlay(alignment: .bottomTrailing) { resizeHandle(for: .bottomTrailing) }
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
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartOffset == nil {
                        dragStartOffset = offset
                        dragStartLocation = value.startLocation
                    }
                    if let startOffset = dragStartOffset, let startLocation = dragStartLocation {
                        offset = CGSize(
                            width: startOffset.width + (value.location.x - startLocation.x),
                            height: startOffset.height + (value.location.y - startLocation.y)
                        )
                    }
                }
                .onEnded { _ in
                    dragStartOffset = nil
                    dragStartLocation = nil
                    commitGeometry()
                }
        )
        .onHover { hovering in
            if hovering {
                NSCursor.openHand.push()
            } else {
                NSCursor.pop()
            }
        }
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
                .onSubmit { submitMessage() }

            if !viewModel.inputText.isEmpty {
                Button(action: submitMessage) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(BrowseColor.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .disabled(viewModel.isStreaming)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
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

    // MARK: - Resize Handles

    private func resizeHandle(for corner: ResizeCorner) -> some View {
        Color.clear
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .gesture(
                resizeGesture(for: corner)
            )
            .overlay {
                Circle()
                    .fill(Color.primary.opacity(0.14))
                    .frame(width: 4, height: 4)
            }
            .onHover { hovering in
                if hovering {
                    NSCursor.crosshair.push()
                } else {
                    NSCursor.pop()
                }
            }
            .padding(4)
    }

    private func resizeGesture(for corner: ResizeCorner) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                beginResizeIfNeeded(for: corner, value: value)
                applyResize(for: corner, value: value)
            }
            .onEnded { _ in
                resetResizeState()
                commitGeometry()
            }
    }

    private func beginResizeIfNeeded(for corner: ResizeCorner, value: DragGesture.Value) {
        guard activeResizeCorner == nil else { return }
        activeResizeCorner = corner
        resizeStartOffset = offset
        resizeStartWidth = paneWidth
        resizeStartHeight = paneHeight
        resizeStartLocation = value.startLocation
    }

    private func applyResize(for corner: ResizeCorner, value: DragGesture.Value) {
        guard activeResizeCorner == corner,
              let startOffset = resizeStartOffset,
              let startWidth = resizeStartWidth,
              let startHeight = resizeStartHeight,
              let startLocation = resizeStartLocation else { return }

        let dx = value.location.x - startLocation.x
        let dy = value.location.y - startLocation.y

        let startRight = startOffset.width
        let startBottom = startOffset.height
        let startLeft = startRight - startWidth
        let startTop = startBottom - startHeight

        let clampedWidth: CGFloat
        let clampedHeight: CGFloat

        switch corner {
        case .topLeading:
            clampedWidth = clamp(startWidth - dx, min: minWidth, max: maxWidth)
            clampedHeight = clamp(startHeight - dy, min: minHeight, max: maxHeight)
            paneWidth = clampedWidth
            paneHeight = clampedHeight
            offset = CGSize(width: startRight, height: startBottom)

        case .topTrailing:
            clampedWidth = clamp(startWidth + dx, min: minWidth, max: maxWidth)
            clampedHeight = clamp(startHeight - dy, min: minHeight, max: maxHeight)
            paneWidth = clampedWidth
            paneHeight = clampedHeight
            offset = CGSize(
                width: startLeft + clampedWidth,
                height: startBottom
            )

        case .bottomLeading:
            clampedWidth = clamp(startWidth - dx, min: minWidth, max: maxWidth)
            clampedHeight = clamp(startHeight + dy, min: minHeight, max: maxHeight)
            paneWidth = clampedWidth
            paneHeight = clampedHeight
            offset = CGSize(
                width: startRight,
                height: startTop + clampedHeight
            )

        case .bottomTrailing:
            clampedWidth = clamp(startWidth + dx, min: minWidth, max: maxWidth)
            clampedHeight = clamp(startHeight + dy, min: minHeight, max: maxHeight)
            paneWidth = clampedWidth
            paneHeight = clampedHeight
            offset = CGSize(
                width: startLeft + clampedWidth,
                height: startTop + clampedHeight
            )
        }
    }

    private func resetResizeState() {
        activeResizeCorner = nil
        resizeStartOffset = nil
        resizeStartWidth = nil
        resizeStartHeight = nil
        resizeStartLocation = nil
    }

    private func commitGeometry() {
        onGeometryCommit(offset, paneWidth, paneHeight)
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
