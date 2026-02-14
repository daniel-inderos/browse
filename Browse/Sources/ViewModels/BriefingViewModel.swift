import SwiftUI

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

    init(query: String, exaClient: ExaAPIClient, claudeClient: ClaudeAPIClient) {
        self.document = BriefingDocument(query: query)
        self.exaClient = exaClient
        self.claudeClient = claudeClient
    }

    @MainActor
    func generate() async {
        phase = .searching
        document.isStreaming = true
        onStateChange?()

        // Phase 1: Search with Exa
        print("[Browse/Briefing] Starting Exa search for: \(document.query)")
        let exaResults: ExaSearchResponse
        do {
            exaResults = try await exaClient.search(query: document.query)
            print("[Browse/Briefing] Exa returned \(exaResults.results.count) results")
        } catch {
            print("[Browse/Briefing] Exa search failed: \(error)")
            phase = .error("Search failed: \(error.localizedDescription)")
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

        print("[Browse/Briefing] Starting Claude stream...")

        let stream = claudeClient.streamMessage(
            system: systemPrompt,
            messages: [ClaudeMessage(role: "user", content: userMessage)]
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
                    print("[Browse/Briefing] Got messageStop. Markdown length: \(document.streamedMarkdown.count)")
                    document.isStreaming = false
                    parseFinal()
                    phase = .complete
                    onStateChange?()

                case .error(let msg):
                    print("[Browse/Briefing] Stream error event: \(msg)")
                    phase = .error(msg)
                    document.isStreaming = false
                    onStateChange?()

                default:
                    break
                }
            }
            // Stream ended without messageStop
            if document.isStreaming {
                print("[Browse/Briefing] Stream ended without messageStop. Got text: \(receivedAnyText), length: \(document.streamedMarkdown.count)")
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
            print("[Browse/Briefing] Stream threw error: \(error)")
            phase = .error("Stream failed: \(error.localizedDescription)")
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
            originalBriefing: document.streamedMarkdown
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
            phase = .error("Follow-up failed: \(error.localizedDescription)")
            document.isStreaming = false
            onStateChange?()
        }
    }

    // MARK: - Incremental Parsing

    private func parseIncrementally() {
        let now = Date()
        guard now.timeIntervalSince(lastParseTime) >= parseInterval else { return }
        lastParseTime = now
        parseMarkdown()
    }

    private func parseFinal() {
        parseMarkdown()
        print("[Browse/Briefing] Parsed: headline='\(document.headline.prefix(50))', tldr='\(document.tldr.prefix(50))', sections=\(document.sections.count)")
    }

    private func parseMarkdown() {
        let md = document.streamedMarkdown

        // Extract headline from first # line (not ##)
        // Always re-parse: during streaming, the line may arrive incrementally
        var foundHeadline = ""
        for line in md.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") && !trimmed.hasPrefix("## ") {
                foundHeadline = String(trimmed.dropFirst(2))
                break
            }
        }
        if !foundHeadline.isEmpty {
            document.headline = foundHeadline
        }

        // Extract TL;DR — always re-parse to capture full text during streaming
        if let range = md.range(of: "**TL;DR:**") ?? md.range(of: "**TL;DR**:") ?? md.range(of: "**TLDR:**") ?? md.range(of: "**TL;DR**") {
            let after = md[range.upperBound...]
            // Take everything until the next double newline or ## header
            let tldrEnd = after.range(of: "\n\n") ?? after.range(of: "\n## ")
            let tldrText: String
            if let end = tldrEnd {
                tldrText = String(after[..<end.lowerBound])
            } else {
                tldrText = String(after)
            }
            let parsed = tldrText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !parsed.isEmpty {
                document.tldr = parsed
            }
        }

        // Parse sections by ## headers
        let lines = md.components(separatedBy: "\n")
        var sections: [BriefingSection] = []
        var currentTitle: String?
        var currentContent: [String] = []

        for line in lines {
            if line.hasPrefix("## ") {
                if let title = currentTitle {
                    let content = currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !content.isEmpty {
                        sections.append(BriefingSection(title: title, content: content))
                    }
                }
                currentTitle = String(line.dropFirst(3))
                currentContent = []
            } else if currentTitle != nil {
                currentContent.append(line)
            }
        }
        if let title = currentTitle {
            let content = currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                sections.append(BriefingSection(title: title, content: content))
            }
        }

        // Preserve identity for sections whose title+position haven't changed,
        // so SwiftUI doesn't treat every streaming re-parse as a remove+insert.
        for i in sections.indices {
            if i < document.sections.count,
               document.sections[i].title == sections[i].title {
                sections[i] = BriefingSection(
                    id: document.sections[i].id,
                    title: sections[i].title,
                    content: sections[i].content
                )
            }
        }
        document.sections = sections
    }
}
