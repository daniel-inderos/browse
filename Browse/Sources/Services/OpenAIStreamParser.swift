import Foundation
import OSLog

private let sseLogger = Logger(subsystem: "com.browse.app", category: "SSE")

struct SSEParser {
    private var currentEvent: String?
    private var dataLines: [String] = []

    mutating func feed(_ line: String) -> OpenAIStreamEvent? {
        if line.hasPrefix("event: ") {
            currentEvent = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            return nil
        }
        if line.hasPrefix("data: ") {
            dataLines.append(String(line.dropFirst(6)))
            return nil
        }
        if line == "data:" {
            dataLines.append("")
            return nil
        }
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            defer { reset() }
            return parseEvent()
        }
        return nil
    }

    /// Call this after the stream ends to flush any pending event.
    mutating func flush() -> OpenAIStreamEvent? {
        guard currentEvent != nil else { return nil }
        defer { reset() }
        return parseEvent()
    }

    private mutating func reset() {
        currentEvent = nil
        dataLines = []
    }

    private func parseEvent() -> OpenAIStreamEvent? {
        guard let event = currentEvent else { return nil }

        let joinedData = dataLines.joined(separator: "\n")
        let jsonData = joinedData.data(using: .utf8)
        let decoder = JSONDecoder()

        switch event {
        case "response.output_text.delta":
            guard let data = jsonData,
                  let payload = try? decoder.decode(OpenAITextDeltaPayload.self, from: data) else {
                sseLogger.warning("Failed to decode SSE event; event=response.output_text.delta, payloadBytes=\(joinedData.utf8.count, privacy: .public)")
                return nil
            }
            return .textDelta(text: payload.delta)

        case "response.completed":
            return .responseCompleted

        case "response.failed":
            guard let data = jsonData,
                  let payload = try? decoder.decode(OpenAIResponseFailedPayload.self, from: data) else {
                sseLogger.warning("Failed to decode SSE event; event=response.failed, payloadBytes=\(joinedData.utf8.count, privacy: .public)")
                return .error("OpenAI response failed")
            }
            return .error(Self.sanitizedError(code: payload.response.error?.code))

        case "error":
            guard let data = jsonData,
                  let payload = try? decoder.decode(OpenAIErrorPayload.self, from: data) else {
                sseLogger.warning("Failed to decode SSE event; event=error, payloadBytes=\(joinedData.utf8.count, privacy: .public)")
                return .error("OpenAI stream error")
            }
            return .error(Self.sanitizedError(code: payload.code))

        default:
            return nil
        }
    }

    private static func sanitizedError(code: String?) -> String {
        guard let code, !code.isEmpty, code.count <= 64,
              code.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
            return "OpenAI stream error"
        }
        return "OpenAI stream error: \(code)"
    }
}
