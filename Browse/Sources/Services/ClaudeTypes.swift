import Foundation

/// A minimal JSON value tree used both to encode request fields whose shape is
/// dynamic (structured-output schemas) and as the result of tolerant parsing
/// of partially streamed JSON.
enum JSONValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let values) = self { return values }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let members) = self { return members[key] }
        return nil
    }
}

extension JSONValue: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let values): try container.encode(values)
        case .object(let members): try container.encode(members)
        }
    }
}

struct ClaudeThinkingConfig: Encodable {
    let type: String

    static let adaptive = ClaudeThinkingConfig(type: "adaptive")
}

struct ClaudeCacheControl: Encodable {
    let type: String

    static let ephemeral = ClaudeCacheControl(type: "ephemeral")
}

struct ClaudeOutputConfig: Encodable {
    let format: Format

    struct Format: Encodable {
        let type: String
        let schema: JSONValue
    }

    static func jsonSchema(_ schema: JSONValue) -> ClaudeOutputConfig {
        ClaudeOutputConfig(format: Format(type: "json_schema", schema: schema))
    }
}

struct ClaudeMessageRequest: Encodable {
    let model: String
    let system: String
    let messages: [ClaudeMessage]
    let maxTokens: Int
    let stream: Bool
    var thinking: ClaudeThinkingConfig?
    var outputConfig: ClaudeOutputConfig?
    var cacheControl: ClaudeCacheControl?

    enum CodingKeys: String, CodingKey {
        case model, system, messages, stream, thinking
        case maxTokens = "max_tokens"
        case outputConfig = "output_config"
        case cacheControl = "cache_control"
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
