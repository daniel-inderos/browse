import SwiftUI

@MainActor
@Observable
final class ChatViewModel {
    var conversationHistory: [ConversationMessage] = []
    var inputText: String = ""
    var streamingResponse: String = ""
    var isStreaming: Bool = false
    var errorMessage: String?
    var onConversationHistoryChange: (([ConversationMessage]) -> Void)?
    private(set) var isPageContextIncluded: Bool = true

    private(set) var pageURL: URL?
    private(set) var pageTitle: String = ""
    private(set) var pageContent: String?

    private let claudeClient: ClaudeAPIClient

    var isStreamingAnswer: Bool {
        isStreaming && !conversationHistory.isEmpty && conversationHistory.last?.role == .user
    }

    var pageContextLabel: String? {
        guard isPageContextIncluded else { return nil }

        let trimmedTitle = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        return pageURL?.displayHost
    }

    init(claudeClient: ClaudeAPIClient) {
        self.claudeClient = claudeClient
    }

    // MARK: - Page Context

    func primePageContext(url: URL?, title: String) {
        pageURL = url
        pageTitle = title
        pageContent = nil
        isPageContextIncluded = true
    }

    func updatePageContext(from webVM: WebTabViewModel) async {
        pageURL = webVM.currentURL
        pageTitle = webVM.pageTitle
        pageContent = await webVM.extractPageContent()
    }

    func removePageContextFromModel() {
        isPageContextIncluded = false
    }

    func resetForNewPage() {
        conversationHistory = []
        streamingResponse = ""
        inputText = ""
        errorMessage = nil
        isStreaming = false
        pageURL = nil
        pageTitle = ""
        pageContent = nil
        isPageContextIncluded = true
        onConversationHistoryChange?(conversationHistory)
    }

    func restoreConversationHistory(_ history: [ConversationMessage]) {
        conversationHistory = history
        streamingResponse = ""
        inputText = ""
        errorMessage = nil
        isStreaming = false
        onConversationHistoryChange?(conversationHistory)
    }

    func clearConversation() {
        conversationHistory = []
        streamingResponse = ""
        inputText = ""
        errorMessage = nil
        isStreaming = false
        onConversationHistoryChange?(conversationHistory)
    }

    // MARK: - Send Message

    func sendMessage(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        conversationHistory.append(ConversationMessage(role: .user, content: trimmed))
        onConversationHistoryChange?(conversationHistory)
        isStreaming = true
        errorMessage = nil
        streamingResponse = ""

        let systemPrompt = buildSystemPrompt()
        let messages = conversationHistory.map {
            ClaudeMessage(role: $0.role.rawValue, content: $0.content)
        }

        var responseText = ""
        let stream = claudeClient.streamMessage(system: systemPrompt, messages: messages)

        do {
            for try await event in stream {
                switch event {
                case .textDelta(let text):
                    responseText += text
                    streamingResponse = responseText

                case .messageStop:
                    streamingResponse = ""
                    conversationHistory.append(
                        ConversationMessage(role: .assistant, content: responseText)
                    )
                    onConversationHistoryChange?(conversationHistory)
                    isStreaming = false

                case .error(let msg):
                    streamingResponse = ""
                    errorMessage = msg
                    isStreaming = false

                default:
                    break
                }
            }
            // Stream ended without messageStop
            if isStreaming {
                if !responseText.isEmpty {
                    conversationHistory.append(
                        ConversationMessage(role: .assistant, content: responseText)
                    )
                    onConversationHistoryChange?(conversationHistory)
                }
                streamingResponse = ""
                isStreaming = false
            }
        } catch {
            streamingResponse = ""
            errorMessage = "Chat failed: \(error.localizedDescription)"
            isStreaming = false
        }
    }

    // MARK: - System Prompt

    func buildSystemPrompt() -> String {
        var prompt = """
        You are Browse, an AI assistant embedded in a native web browser.

        """

        if isPageContextIncluded {
            prompt += "The user is currently viewing a web page and wants to discuss it with you.\n\n"

            if let url = pageURL {
                prompt += "Current page URL: \(url.absoluteString)\n"
            }
            if !pageTitle.isEmpty {
                prompt += "Page title: \(pageTitle)\n"
            }
            if let content = pageContent, !content.isEmpty {
                prompt += "\nPage content (truncated):\n\(content)\n"
            }
        } else {
            prompt += "No current page context is attached to this chat request.\n"
        }

        if isPageContextIncluded {
            prompt += """

            RULES:
            - Answer questions about the page content directly and helpfully
            - Be conversational but precise
            - When referencing specific parts of the page, be specific
            - Use markdown formatting for clarity (bold, bullets, code blocks)
            - If the user asks about something not on the page, say so honestly
            - Keep responses focused and concise unless the user asks for detail
            """
        } else {
            prompt += """

            RULES:
            - Be conversational but precise
            - Use markdown formatting for clarity (bold, bullets, code blocks)
            - Do not infer details from the current browser page because it was not provided
            - Keep responses focused and concise unless the user asks for detail
            """
        }

        return prompt
    }
}
