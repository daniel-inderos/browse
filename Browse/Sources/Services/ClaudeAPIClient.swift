import Foundation

enum ClaudeAPIError: Error, LocalizedError {
    case noAPIKey
    case httpError(statusCode: Int, body: String)
    case decodingError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "Claude API key not configured. Open Settings to add it."
        case .httpError(let code, let body): "HTTP \(code): \(body)"
        case .decodingError(let msg): "Decoding error: \(msg)"
        case .networkError(let err): "Network error: \(err.localizedDescription)"
        }
    }
}

final class ClaudeAPIClient: Sendable {
    private let getAPIKey: @Sendable () -> String?
    private let session: URLSession
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-opus-4-7"

    init(getAPIKey: @escaping @Sendable () -> String?, session: URLSession = .shared) {
        self.getAPIKey = getAPIKey
        self.session = session
    }

    func streamMessage(
        system: String,
        messages: [ClaudeMessage],
        maxTokens: Int = 4096
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

                    let body = ClaudeMessageRequest(
                        model: model,
                        system: system,
                        messages: messages,
                        maxTokens: maxTokens,
                        stream: true
                    )
                    request.httpBody = try JSONEncoder().encode(body)

                    print("[Browse/Claude] Sending request, model=\(self.model), system=\(system.count) chars, user=\(messages.first?.content.count ?? 0) chars")

                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: ClaudeAPIError.networkError(
                            NSError(domain: "ClaudeAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                        ))
                        return
                    }

                    print("[Browse/Claude] HTTP \(httpResponse.statusCode)")

                    // For non-200, read the full body as error
                    guard httpResponse.statusCode == 200 else {
                        var errorBody = Data()
                        for try await byte in bytes {
                            errorBody.append(byte)
                            if errorBody.count > 2000 { break }
                        }
                        let errorStr = String(data: errorBody, encoding: .utf8) ?? "Unknown error"
                        print("[Browse/Claude] Error body: \(errorStr.prefix(500))")
                        continuation.finish(throwing: ClaudeAPIError.httpError(
                            statusCode: httpResponse.statusCode, body: errorStr
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
                                    print("[Browse/Claude] Complete: \(eventCount) events, \(textLength) chars")
                                    continuation.finish()
                                    return
                                }
                                if case .error(let msg) = event {
                                    print("[Browse/Claude] Error event: \(msg)")
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

                    print("[Browse/Claude] Stream ended: \(eventCount) events, \(textLength) chars")
                    continuation.finish()
                } catch {
                    print("[Browse/Claude] Exception: \(error)")
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

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = ClaudeMessageRequest(
            model: model,
            system: "Reply with OK.",
            messages: [ClaudeMessage(role: "user", content: "ping")],
            maxTokens: 10,
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }
}
