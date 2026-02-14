import Foundation

struct ClaudeMessageRequest: Encodable {
    let model: String
    let system: String
    let messages: [ClaudeMessage]
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, system, messages, stream
        case maxTokens = "max_tokens"
    }
}

struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

// MARK: - Stream Response Types

enum ClaudeStreamEvent {
    case messageStart(messageId: String, model: String)
    case contentBlockStart(index: Int)
    case textDelta(text: String)
    case contentBlockStop(index: Int)
    case messageDelta(stopReason: String?)
    case messageStop
    case ping
    case error(String)
}

// Internal decoding helpers

struct ClaudeMessageStartPayload: Decodable {
    let type: String
    let message: MessageInfo

    struct MessageInfo: Decodable {
        let id: String
        let model: String
    }
}

struct ClaudeContentBlockStartPayload: Decodable {
    let type: String
    let index: Int
}

struct ClaudeContentBlockDeltaPayload: Decodable {
    let type: String
    let index: Int
    let delta: Delta

    struct Delta: Decodable {
        let type: String
        let text: String?
    }
}

struct ClaudeContentBlockStopPayload: Decodable {
    let type: String
    let index: Int
}

struct ClaudeMessageDeltaPayload: Decodable {
    let type: String
    let delta: Delta

    struct Delta: Decodable {
        let stopReason: String?
        enum CodingKeys: String, CodingKey {
            case stopReason = "stop_reason"
        }
    }
}

struct ClaudeErrorPayload: Decodable {
    let type: String
    let error: ErrorInfo

    struct ErrorInfo: Decodable {
        let type: String
        let message: String
    }
}
