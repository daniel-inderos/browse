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

struct OpenAIReasoningConfig: Encodable {
    let effort: String

    static let medium = OpenAIReasoningConfig(effort: "medium")
}

struct OpenAITextConfig: Encodable {
    let format: Format

    struct Format: Encodable {
        let type: String
        let name: String
        let strict: Bool
        let schema: JSONValue
    }

    static func jsonSchema(_ schema: JSONValue, name: String = "browse_response") -> OpenAITextConfig {
        OpenAITextConfig(format: Format(
            type: "json_schema",
            name: name,
            strict: true,
            schema: schema
        ))
    }
}

struct OpenAIResponseRequest: Encodable {
    let model: String
    let instructions: String
    let input: [OpenAIMessage]
    let maxOutputTokens: Int
    let stream: Bool
    let store: Bool
    var reasoning: OpenAIReasoningConfig?
    var text: OpenAITextConfig?

    enum CodingKeys: String, CodingKey {
        case model, instructions, input, stream, store, reasoning, text
        case maxOutputTokens = "max_output_tokens"
    }
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

enum OpenAIStreamEvent {
    case textDelta(text: String)
    case responseCompleted
    case error(String)
}

struct OpenAITextDeltaPayload: Decodable {
    let delta: String
}

struct OpenAIResponseFailedPayload: Decodable {
    let response: ResponseInfo

    struct ResponseInfo: Decodable {
        let error: OpenAIErrorInfo?
    }
}

struct OpenAIErrorPayload: Decodable {
    let code: String?
}

struct OpenAIErrorInfo: Decodable {
    let code: String?
}
