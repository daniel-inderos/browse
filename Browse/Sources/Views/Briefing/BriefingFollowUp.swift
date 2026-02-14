import SwiftUI
import MarkdownUI

struct BriefingFollowUp: View {
    @Bindable var viewModel: BriefingViewModel
    var showConversationHistory: Bool = true
    var showInput: Bool = true
    var isFloating: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showConversationHistory {
                conversationHistoryView
            }

            if showInput {
                followUpInputView
            }
        }
    }

    // MARK: - Conversation History (Brief Continuation Style)

    @ViewBuilder
    private var conversationHistoryView: some View {
        if !viewModel.conversationHistory.isEmpty {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(followUpPairs) { pair in
                    FollowUpSectionView(
                        question: pair.question,
                        answer: pair.answer,
                        streamingAnswer: pair.answer == nil ? viewModel.streamingFollowUp : nil,
                        isStreaming: pair.answer == nil && viewModel.isStreamingFollowUp
                    )
                }
            }
        }
    }

    // MARK: - Follow-Up Input

    private var followUpInputView: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.bubble")
                .foregroundStyle(.quaternary)
                .font(.system(size: 14))

            TextField("Ask a follow-up…", text: $viewModel.followUpText)
                .textFieldStyle(.plain)
                .font(BrowseFont.conversationBody)
                .onSubmit { submitFollowUp() }

            if !viewModel.followUpText.isEmpty {
                Button(action: submitFollowUp) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(BrowseColor.accent)
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .disabled(viewModel.document.isStreaming)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isFloating
                        ? Color(nsColor: .controlBackgroundColor).opacity(0.96)
                        : BrowseColor.surfaceSubtle
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isFloating ? Color.primary.opacity(0.14) : BrowseColor.borderSubtle,
                    lineWidth: isFloating ? 0.75 : 0.5
                )
        )
        .shadow(
            color: isFloating ? BrowseColor.shadowSubtle.opacity(0.5) : .clear,
            radius: isFloating ? 6 : 0,
            x: 0,
            y: isFloating ? 2 : 0
        )
    }

    private func submitFollowUp() {
        let question = viewModel.followUpText
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        viewModel.followUpText = ""
        Task {
            await viewModel.askFollowUp(question)
        }
    }

    // MARK: - Pair Computation

    private var followUpPairs: [FollowUpPair] {
        var pairs: [FollowUpPair] = []
        let messages = viewModel.conversationHistory
        var i = 0
        while i < messages.count {
            if messages[i].role == .user {
                let question = messages[i]
                if i + 1 < messages.count && messages[i + 1].role == .assistant {
                    pairs.append(FollowUpPair(
                        id: question.id,
                        question: question.content,
                        answer: messages[i + 1].content
                    ))
                    i += 2
                } else {
                    pairs.append(FollowUpPair(
                        id: question.id,
                        question: question.content,
                        answer: nil
                    ))
                    i += 1
                }
            } else {
                i += 1
            }
        }
        return pairs
    }
}

// MARK: - Follow-Up Pair

private struct FollowUpPair: Identifiable {
    let id: UUID
    let question: String
    let answer: String?
}

// MARK: - Follow-Up Section (Brief Continuation Style)

private struct FollowUpSectionView: View {
    let question: String
    let answer: String?
    let streamingAnswer: String?
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section title — the user's question, styled like a briefing section header
            VStack(alignment: .leading, spacing: 6) {
                Text(question)
                    .font(BrowseFont.briefingSectionTitle)
                    .foregroundStyle(.primary)

                RoundedRectangle(cornerRadius: 1)
                    .fill(BrowseColor.accent.opacity(0.2))
                    .frame(width: 28, height: 2)
            }

            // Section body — completed answer or streaming partial
            if let answer = answer {
                Markdown(answer)
                    .markdownTheme(.browseEditorial)
                    .padding(.top, 2)
            } else if let streaming = streamingAnswer, !streaming.isEmpty {
                Markdown(streaming)
                    .markdownTheme(.browseEditorial)
                    .padding(.top, 2)
            }

            // Streaming indicator — pulsing dot with optional "Thinking…" label
            if isStreaming {
                HStack(spacing: 8) {
                    Circle()
                        .fill(BrowseColor.accent)
                        .frame(width: 6, height: 6)
                        .modifier(PulsingDot())

                    if streamingAnswer?.isEmpty ?? true {
                        Text("Thinking…")
                            .font(BrowseFont.briefingCaption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}
