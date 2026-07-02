import SwiftUI
import OSLog

private let briefingLogger = Logger(subsystem: "com.browse.app", category: "Briefing")

enum BriefingPhase: Equatable {
    case idle
    case searching
    case synthesizing
    case complete
    case error(String)
}

@Observable
final class BriefingViewModel {
    var document: BriefingDocument
    var phase: BriefingPhase = .idle
    var conversationHistory: [ConversationMessage] = []
    var followUpText: String = ""
    var streamingFollowUp: String = ""
    var onStateChange: (() -> Void)?

    var isStreamingFollowUp: Bool {
        document.isStreaming && !conversationHistory.isEmpty && conversationHistory.last?.role == .user
    }

    private let exaClient: ExaAPIClient
    private let claudeClient: ClaudeAPIClient
    private let composer = BriefingComposer()

    private var lastParseTime: Date = .distantPast
    private let parseInterval: TimeInterval = 0.15
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var generationRunID = UUID()

    init(query: String, exaClient: ExaAPIClient, claudeClient: ClaudeAPIClient) {
        self.document = BriefingDocument(query: query)
        self.exaClient = exaClient
        self.claudeClient = claudeClient
    }

    deinit {
        generationTask?.cancel()
    }

    @MainActor
    func startGeneration() {
        generationTask?.cancel()

        let runID = UUID()
        generationRunID = runID
        generationTask = Task { [weak self] in
            guard let self else { return }
            await self.generate()
            await MainActor.run { [weak self] in
                guard let self, self.generationRunID == runID else { return }
                self.generationTask = nil
            }
        }
    }

    @MainActor
    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        guard document.isStreaming else { return }
        document.isStreaming = false
        onStateChange?()
    }

    @MainActor
    func generate() async {
        phase = .searching
        document.isStreaming = true
        onStateChange?()

        // Phase 1: Search with Exa
        briefingLogger.info("Starting Exa search; queryLength=\(self.document.query.count, privacy: .public)")
        let exaResults: ExaSearchResponse
        do {
            exaResults = try await exaClient.search(query: document.query)
            briefingLogger.info("Exa search completed; resultCount=\(exaResults.results.count, privacy: .public)")
        } catch {
            briefingLogger.error("Exa search failed; category=\(Self.errorCategory(error), privacy: .public)")
            phase = .error(Self.userFacingErrorMessage(error, operation: "Search"))
            document.isStreaming = false
            onStateChange?()
            return
        }

        // Build sources from results
        document.sources = exaResults.results.compactMap { result in
            guard let url = URL(string: result.url) else { return nil }
            return Source(
                title: result.title,
                url: url,
                snippet: result.highlights?.first ?? String(result.text?.prefix(200) ?? ""),
                faviconURL: result.favicon.flatMap { URL(string: $0) },
                imageURL: result.image.flatMap { URL(string: $0) },
                publishedDate: result.publishedDate,
                author: result.author
            )
        }
        onStateChange?()

        // Phase 2: Stream from Claude
        phase = .synthesizing
        document.streamedMarkdown = ""

        let systemPrompt = composer.buildSystemPrompt()
        let userMessage = composer.buildUserMessage(query: document.query, sources: exaResults.results)

        briefingLogger.info("Starting Claude stream; sourceCount=\(exaResults.results.count, privacy: .public)")

        let stream = claudeClient.streamMessage(
            system: systemPrompt,
            messages: [ClaudeMessage(role: "user", content: userMessage)],
            outputSchema: BriefingComposer.briefingSchema
        )

        var receivedAnyText = false

        do {
            for try await event in stream {
                switch event {
                case .textDelta(let text):
                    document.streamedMarkdown += text
                    receivedAnyText = true
                    parseIncrementally()

                case .messageStop:
                    briefingLogger.info("Claude stream completed; markdownLength=\(self.document.streamedMarkdown.count, privacy: .public)")
                    document.isStreaming = false
                    parseFinal()
                    phase = .complete
                    onStateChange?()

                case .error(let msg):
                    briefingLogger.error("Claude stream returned error event; messageLength=\(msg.count, privacy: .public)")
                    phase = .error(msg)
                    document.isStreaming = false
                    onStateChange?()

                default:
                    break
                }
            }
            // Stream ended without messageStop
            if document.isStreaming {
                briefingLogger.warning("Claude stream ended without messageStop; receivedText=\(receivedAnyText, privacy: .public), markdownLength=\(self.document.streamedMarkdown.count, privacy: .public)")
                document.isStreaming = false
                if receivedAnyText {
                    parseFinal()
                    phase = .complete
                } else {
                    phase = .error("Claude returned no content. The request may have been too large or the API key may be invalid.")
                }
                onStateChange?()
            }
        } catch {
            briefingLogger.error("Claude stream failed; category=\(Self.errorCategory(error), privacy: .public)")
            phase = .error(Self.userFacingErrorMessage(error, operation: "Stream"))
            document.isStreaming = false
            onStateChange?()
        }
    }

    @MainActor
    func askFollowUp(_ question: String) async {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        conversationHistory.append(ConversationMessage(role: .user, content: question))
        phase = .synthesizing
        document.isStreaming = true
        onStateChange?()

        let systemPrompt = composer.buildFollowUpSystemPrompt(
            originalQuery: document.query,
            originalBriefing: document.renderedMarkdown
        )

        var messages: [ClaudeMessage] = []
        for msg in conversationHistory {
            messages.append(ClaudeMessage(role: msg.role.rawValue, content: msg.content))
        }

        var followUpResponse = ""
        streamingFollowUp = ""
        let stream = claudeClient.streamMessage(system: systemPrompt, messages: messages)

        do {
            for try await event in stream {
                switch event {
                case .textDelta(let text):
                    followUpResponse += text
                    streamingFollowUp = followUpResponse

                case .messageStop:
                    streamingFollowUp = ""
                    conversationHistory.append(ConversationMessage(role: .assistant, content: followUpResponse))
                    document.isStreaming = false
                    phase = .complete
                    onStateChange?()

                case .error(let msg):
                    streamingFollowUp = ""
                    phase = .error(msg)
                    document.isStreaming = false
                    onStateChange?()

                default:
                    break
                }
            }
            if document.isStreaming {
                if !followUpResponse.isEmpty {
                    conversationHistory.append(ConversationMessage(role: .assistant, content: followUpResponse))
                }
                streamingFollowUp = ""
                document.isStreaming = false
                phase = .complete
                onStateChange?()
            }
        } catch {
            streamingFollowUp = ""
            briefingLogger.error("Claude follow-up failed; category=\(Self.errorCategory(error), privacy: .public)")
            phase = .error(Self.userFacingErrorMessage(error, operation: "Follow-up"))
            document.isStreaming = false
            onStateChange?()
        }
    }

    // MARK: - Incremental Parsing

    private func parseIncrementally() {
        let now = Date()
        guard now.timeIntervalSince(lastParseTime) >= parseInterval else { return }
        lastParseTime = now
        parseStreamedJSON()
    }

    private func parseFinal() {
        parseStreamedJSON()
        // Structured outputs guarantee valid JSON on success, but if nothing
        // parsed and we still have text, surface it rather than a blank page.
        if document.headline.isEmpty, document.sections.isEmpty,
           !document.streamedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            document.sections = [BriefingSection(title: "Briefing", content: document.streamedMarkdown)]
        }
        briefingLogger.debug("Parsed briefing; headlineLength=\(self.document.headline.count, privacy: .public), tldrLength=\(self.document.tldr.count, privacy: .public), sections=\(self.document.sections.count, privacy: .public)")
    }

    private func parseStreamedJSON() {
        guard let parsed = BriefingStreamParser.parse(
            document.streamedMarkdown,
            existingSections: document.sections
        ) else { return }

        if !parsed.headline.isEmpty {
            document.headline = parsed.headline
        }
        if !parsed.tldr.isEmpty {
            document.tldr = parsed.tldr
        }
        if !parsed.sections.isEmpty || !document.sections.isEmpty {
            document.sections = parsed.sections
        }
    }

    private static func errorCategory(_ error: Error) -> String {
        switch error {
        case ClaudeAPIError.noAPIKey, ExaAPIError.noAPIKey:
            return "missing-api-key"
        case ClaudeAPIError.httpError(let statusCode, _), ExaAPIError.httpError(let statusCode, _):
            return "http-\(statusCode)"
        case ClaudeAPIError.decodingError, ExaAPIError.decodingError:
            return "decoding"
        case ClaudeAPIError.networkError, ExaAPIError.networkError:
            return "network"
        case is CancellationError:
            return "cancelled"
        default:
            return "unknown"
        }
    }

    private static func userFacingErrorMessage(_ error: Error, operation: String) -> String {
        switch error {
        case ClaudeAPIError.noAPIKey, ExaAPIError.noAPIKey:
            return "\(operation) failed: API key not configured. Add it to .env."
        case ClaudeAPIError.httpError(let statusCode, _), ExaAPIError.httpError(let statusCode, _):
            return "\(operation) failed: provider returned HTTP \(statusCode)."
        case ClaudeAPIError.decodingError, ExaAPIError.decodingError:
            return "\(operation) failed: provider response could not be decoded."
        case ClaudeAPIError.networkError, ExaAPIError.networkError:
            return "\(operation) failed: network error."
        case is CancellationError:
            return "\(operation) cancelled."
        default:
            return "\(operation) failed."
        }
    }
}
