import Foundation
import OSLog

private let openAILogger = Logger(subsystem: "com.browse.app", category: "OpenAI")

enum OpenAIAPIError: Error, LocalizedError {
    case noAPIKey
    case httpError(statusCode: Int, body: String)
    case decodingError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "OpenAI API key not configured. Add OPENAI_API_KEY to .env."
        case .httpError(let code, _): "HTTP \(code)"
        case .decodingError: "Decoding error"
        case .networkError: "Network error"
        }
    }
}

final class OpenAIAPIClient: Sendable {
    private let getAPIKey: @Sendable () -> String?
    private let session: URLSession
    private let baseURL = URL(string: "https://api.openai.com/v1/responses")!
    private let model = "gpt-5.6-terra"

    init(getAPIKey: @escaping @Sendable () -> String?, session: URLSession = .shared) {
        self.getAPIKey = getAPIKey
        self.session = session
    }

    func streamMessage(
        system: String,
        messages: [OpenAIMessage],
        maxTokens: Int = 16000,
        outputSchema: JSONValue? = nil
    ) -> AsyncThrowingStream<OpenAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let apiKey = getAPIKey() else {
                        continuation.finish(throwing: OpenAIAPIError.noAPIKey)
                        return
                    }

                    var request = URLRequest(url: baseURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.timeoutInterval = 120

                    let body = OpenAIResponseRequest(
                        model: model,
                        instructions: system,
                        input: messages,
                        maxOutputTokens: maxTokens,
                        stream: true,
                        store: false,
                        reasoning: .medium,
                        text: outputSchema.map { .jsonSchema($0, name: "briefing") }
                    )
                    request.httpBody = try JSONEncoder().encode(body)

                    let messageCharacterCount = messages.reduce(0) { $0 + $1.content.count }
                    openAILogger.info("Sending stream request; model=\(self.model, privacy: .public), systemChars=\(system.count, privacy: .public), messageCount=\(messages.count, privacy: .public), messageChars=\(messageCharacterCount, privacy: .public)")

                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: OpenAIAPIError.networkError(
                            NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                        ))
                        return
                    }

                    openAILogger.info("Received stream response; statusCode=\(httpResponse.statusCode, privacy: .public)")

                    guard httpResponse.statusCode == 200 else {
                        var errorBody = Data()
                        for try await byte in bytes {
                            errorBody.append(byte)
                            if errorBody.count > 2000 { break }
                        }
                        let redactedBodySummary = "redacted \(errorBody.count) bytes"
                        openAILogger.error("Stream request failed; statusCode=\(httpResponse.statusCode, privacy: .public), bodyBytes=\(errorBody.count, privacy: .public)")
                        continuation.finish(throwing: OpenAIAPIError.httpError(
                            statusCode: httpResponse.statusCode,
                            body: redactedBodySummary
                        ))
                        return
                    }

                    var lineBuffer = Data()
                    var sseParser = SSEParser()
                    var eventCount = 0
                    var textLength = 0

                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
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

                                if case .responseCompleted = event {
                                    openAILogger.info("Stream completed; eventCount=\(eventCount, privacy: .public), textChars=\(textLength, privacy: .public)")
                                    continuation.finish()
                                    return
                                }
                                if case .error(let message) = event {
                                    openAILogger.error("Stream returned error event; messageLength=\(message.count, privacy: .public)")
                                    continuation.finish(throwing: OpenAIAPIError.decodingError(message))
                                    return
                                }
                            }
                        } else {
                            lineBuffer.append(byte)
                        }
                    }

                    if !lineBuffer.isEmpty {
                        let line = String(data: lineBuffer, encoding: .utf8) ?? ""
                        if let event = sseParser.feed(line) {
                            eventCount += 1
                            continuation.yield(event)
                        }
                    }
                    if let event = sseParser.flush() {
                        eventCount += 1
                        continuation.yield(event)
                    }

                    openAILogger.info("Stream ended; eventCount=\(eventCount, privacy: .public), textChars=\(textLength, privacy: .public)")
                    continuation.finish()
                } catch {
                    openAILogger.error("Stream request threw; category=\(Self.errorCategory(error), privacy: .public)")
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
            throw OpenAIAPIError.noAPIKey
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models/\(model)")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }

    private static func errorCategory(_ error: Error) -> String {
        switch error {
        case OpenAIAPIError.noAPIKey:
            return "missing-api-key"
        case OpenAIAPIError.httpError(let statusCode, _):
            return "http-\(statusCode)"
        case OpenAIAPIError.decodingError:
            return "decoding"
        case OpenAIAPIError.networkError:
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
