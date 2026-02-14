import Foundation

struct SSEParser {
    private var currentEvent: String?
    private var dataLines: [String] = []
    private var hasData = false

    mutating func feed(_ line: String) -> ClaudeStreamEvent? {
        // SSE format: "event: <type>\ndata: <json>\n\n"
        // Blank line signals end of event
        if line.hasPrefix("event: ") {
            currentEvent = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            return nil
        } else if line.hasPrefix("data: ") {
            dataLines.append(String(line.dropFirst(6)))
            hasData = true
            return nil
        } else if line == "data:" {
            // Empty data line
            dataLines.append("")
            hasData = true
            return nil
        } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
            // Blank line — dispatch the event
            defer {
                currentEvent = nil
                dataLines = []
                hasData = false
            }
            if currentEvent != nil {
                return parseEvent()
            }
            return nil
        }
        // Unknown line format — could be a continuation
        return nil
    }

    /// Call this after the stream ends to flush any pending event
    mutating func flush() -> ClaudeStreamEvent? {
        guard currentEvent != nil else { return nil }
        defer {
            currentEvent = nil
            dataLines = []
            hasData = false
        }
        return parseEvent()
    }

    private func parseEvent() -> ClaudeStreamEvent? {
        guard let event = currentEvent else { return nil }

        let joinedData = dataLines.joined(separator: "\n")
        let jsonData = joinedData.data(using: .utf8)

        let decoder = JSONDecoder()

        switch event {
        case "message_start":
            guard let data = jsonData,
                  let payload = try? decoder.decode(ClaudeMessageStartPayload.self, from: data) else {
                print("[Browse/SSE] Failed to decode message_start: \(joinedData.prefix(200))")
                return nil
            }
            return .messageStart(messageId: payload.message.id, model: payload.message.model)

        case "content_block_start":
            guard let data = jsonData,
                  let payload = try? decoder.decode(ClaudeContentBlockStartPayload.self, from: data) else {
                print("[Browse/SSE] Failed to decode content_block_start: \(joinedData.prefix(200))")
                return nil
            }
            return .contentBlockStart(index: payload.index)

        case "content_block_delta":
            guard let data = jsonData,
                  let payload = try? decoder.decode(ClaudeContentBlockDeltaPayload.self, from: data) else {
                print("[Browse/SSE] Failed to decode content_block_delta: \(joinedData.prefix(200))")
                return nil
            }
            if let text = payload.delta.text {
                return .textDelta(text: text)
            }
            return nil

        case "content_block_stop":
            guard let data = jsonData,
                  let payload = try? decoder.decode(ClaudeContentBlockStopPayload.self, from: data) else {
                print("[Browse/SSE] Failed to decode content_block_stop: \(joinedData.prefix(200))")
                return nil
            }
            return .contentBlockStop(index: payload.index)

        case "message_delta":
            guard let data = jsonData,
                  let payload = try? decoder.decode(ClaudeMessageDeltaPayload.self, from: data) else {
                print("[Browse/SSE] Failed to decode message_delta: \(joinedData.prefix(200))")
                return nil
            }
            return .messageDelta(stopReason: payload.delta.stopReason)

        case "message_stop":
            return .messageStop

        case "ping":
            return .ping

        case "error":
            guard let data = jsonData,
                  let payload = try? decoder.decode(ClaudeErrorPayload.self, from: data) else {
                return .error("Unknown error: \(joinedData.prefix(200))")
            }
            return .error(payload.error.message)

        default:
            print("[Browse/SSE] Unknown event type: \(event)")
            return nil
        }
    }
}
