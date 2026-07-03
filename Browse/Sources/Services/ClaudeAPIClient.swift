import Foundation
import OSLog

private let claudeLogger = Logger(subsystem: "com.browse.app", category: "Claude")

enum ClaudeAPIError: Error, LocalizedError {
    case noAPIKey
    case httpError(statusCode: Int, body: String)
    case decodingError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "Claude API key not configured. Add ANTHROPIC_API_KEY to .env."
        case .httpError(let code, _): "HTTP \(code)"
        case .decodingError: "Decoding error"
        case .networkError: "Network error"
        }
    }
}

final class ClaudeAPIClient: Sendable {
    private let getAPIKey: @Sendable () -> String?
    private let session: URLSession
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-opus-4-8"

    init(getAPIKey: @escaping @Sendable () -> String?, session: URLSession = .shared) {
        self.getAPIKey = getAPIKey
        self.session = session
    }

    func streamMessage(
        system: String,
        messages: [ClaudeMessage],
        maxTokens: Int = 16000,
        outputSchema: JSONValue? = nil
    ) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let apiKey = getAPIKey() else {
                        continuation.finish(throwing: ClaudeAPIError.noAPIKey)
                        return
                    }

                    var request = URLRequest(url: baseURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.timeoutInterval = 120

                    // Adaptive thinking lets the model decide how much to reason;
                    // the top-level cache_control auto-caches the request prefix so
                    // follow-up turns re-read the system prompt and history at ~10%
                    // of input cost instead of re-processing them.
                    let body = ClaudeMessageRequest(
                        model: model,
                        system: system,
                        messages: messages,
                        maxTokens: maxTokens,
                        stream: true,
                        thinking: .adaptive,
                        outputConfig: outputSchema.map { ClaudeOutputConfig.jsonSchema($0) },
                        cacheControl: .ephemeral
                    )
                    request.httpBody = try JSONEncoder().encode(body)

                    let messageCharacterCount = messages.reduce(0) { $0 + $1.content.count }
                    claudeLogger.info("Sending stream request; model=\(self.model, privacy: .public), systemChars=\(system.count, privacy: .public), messageCount=\(messages.count, privacy: .public), messageChars=\(messageCharacterCount, privacy: .public)")

                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: ClaudeAPIError.networkError(
                            NSError(domain: "ClaudeAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                        ))
                        return
                    }

                    claudeLogger.info("Received stream response; statusCode=\(httpResponse.statusCode, privacy: .public)")

                    // For non-200, read the full body as error
                    guard httpResponse.statusCode == 200 else {
                        var errorBody = Data()
                        for try await byte in bytes {
                            errorBody.append(byte)
                            if errorBody.count > 2000 { break }
                        }
                        let redactedBodySummary = "redacted \(errorBody.count) bytes"
                        claudeLogger.error("Stream request failed; statusCode=\(httpResponse.statusCode, privacy: .public), bodyBytes=\(errorBody.count, privacy: .public)")
                        continuation.finish(throwing: ClaudeAPIError.httpError(
                            statusCode: httpResponse.statusCode,
                            body: redactedBodySummary
                        ))
                        return
                    }

                    // Buffer raw bytes and decode full lines as UTF-8.
                    // This avoids splitting multi-byte characters (e.g. em dash "—")
                    // that span across individual bytes.
                    var lineBuffer = Data()
                    var sseParser = SSEParser()
                    var eventCount = 0
                    var textLength = 0

                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            // Strip trailing \r if present (handles \r\n line endings)
                            if lineBuffer.last == UInt8(ascii: "\r") {
                                lineBuffer.removeLast()
                            }
                            let line = String(data: lineBuffer, encoding: .utf8) ?? ""
                            lineBuffer.removeAll(keepingCapacity: true)

                            if let event = sseParser.feed(line) {
                                eventCount += 1
                                if case .textDelta(let text) = event {
                                    textLength += text.count
                                }
                                continuation.yield(event)

                                if case .messageStop = event {
                                    claudeLogger.info("Stream completed; eventCount=\(eventCount, privacy: .public), textChars=\(textLength, privacy: .public)")
                                    continuation.finish()
                                    return
                                }
                                if case .error(let msg) = event {
                                    claudeLogger.error("Stream returned error event; messageLength=\(msg.count, privacy: .public)")
                                    continuation.finish(throwing: ClaudeAPIError.decodingError(msg))
                                    return
                                }
                            }
                        } else {
                            lineBuffer.append(byte)
                        }
                    }

                    // Flush any remaining bytes as a final line
                    if !lineBuffer.isEmpty {
                        let line = String(data: lineBuffer, encoding: .utf8) ?? ""
                        if let event = sseParser.feed(line) {
                            eventCount += 1
                            continuation.yield(event)
                        }
                    }
                    // Flush the SSE parser for any pending event
                    if let event = sseParser.flush() {
                        eventCount += 1
                        continuation.yield(event)
                    }

                    claudeLogger.info("Stream ended; eventCount=\(eventCount, privacy: .public), textChars=\(textLength, privacy: .public)")
                    continuation.finish()
                } catch {
                    claudeLogger.error("Stream request threw; category=\(Self.errorCategory(error), privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func testConnection() async throws -> Bool {
        guard let apiKey = getAPIKey() else {
            throw ClaudeAPIError.noAPIKey
        }

        // Retrieving the model's metadata validates the key and model
        // availability without spending output tokens on a completion.
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models/\(model)")!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }

    private static func errorCategory(_ error: Error) -> String {
        switch error {
        case ClaudeAPIError.noAPIKey:
            return "missing-api-key"
        case ClaudeAPIError.httpError(let statusCode, _):
            return "http-\(statusCode)"
        case ClaudeAPIError.decodingError:
            return "decoding"
        case ClaudeAPIError.networkError:
            return "network"
        case is DecodingError:
            return "decoding"
        case is EncodingError:
            return "encoding"
        case is CancellationError:
            return "cancelled"
        case let urlError as URLError:
            return "url-\(urlError.errorCode)"
        default:
            return "unknown"
        }
    }
}
