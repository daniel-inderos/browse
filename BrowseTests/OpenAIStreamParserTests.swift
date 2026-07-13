import Foundation
import Testing
@testable import Browse

@Suite("OpenAI SSE parser")
struct OpenAIStreamParserTests {
    private func feedLines(_ lines: [String]) -> [OpenAIStreamEvent] {
        var parser = SSEParser()
        var events: [OpenAIStreamEvent] = []
        for line in lines {
            if let event = parser.feed(line) {
                events.append(event)
            }
        }
        if let event = parser.flush() {
            events.append(event)
        }
        return events
    }

    @Test("Parses a complete text stream transcript")
    func parsesFullTranscript() {
        let events = feedLines([
            "event: response.created",
            #"data: {"type":"response.created","response":{"id":"resp_01","model":"gpt-5.6-terra"}}"#,
            "",
            "event: response.output_text.delta",
            #"data: {"type":"response.output_text.delta","delta":"Hello"}"#,
            "",
            "event: response.output_text.delta",
            #"data: {"type":"response.output_text.delta","delta":" world"}"#,
            "",
            "event: response.completed",
            #"data: {"type":"response.completed","response":{"id":"resp_01","status":"completed"}}"#,
            "",
        ])

        guard events.count == 3 else {
            Issue.record("Expected 3 events, got \(events.count)")
            return
        }
        guard case .textDelta(let first) = events[0],
              case .textDelta(let second) = events[1] else {
            Issue.record("Expected text deltas")
            return
        }
        #expect(first + second == "Hello world")
        guard case .responseCompleted = events[2] else {
            Issue.record("Expected responseCompleted")
            return
        }
    }

    @Test("Reasoning events produce no app event")
    func ignoresReasoningEvents() {
        let events = feedLines([
            "event: response.reasoning_summary_text.delta",
            #"data: {"type":"response.reasoning_summary_text.delta","delta":"hmm"}"#,
            "",
        ])

        #expect(events.isEmpty)
    }

    @Test("Error event codes are sanitized")
    func sanitizesErrorEvents() {
        let events = feedLines([
            "event: error",
            #"data: {"type":"error","code":"server_error","message":"Sensitive provider detail"}"#,
            "",
        ])

        guard case .error(let message) = events.first else {
            Issue.record("Expected error event")
            return
        }
        #expect(message.contains("server_error"))
        #expect(!message.contains("Sensitive provider detail"))
    }

    @Test("Suspicious error codes are omitted")
    func replacesSuspiciousErrorCode() {
        let events = feedLines([
            "event: error",
            #"data: {"type":"error","code":"weird code; drop table","message":"x"}"#,
            "",
        ])

        guard case .error(let message) = events.first else {
            Issue.record("Expected error event")
            return
        }
        #expect(message == "OpenAI stream error")
        #expect(!message.contains("drop table"))
    }

    @Test("Response failures surface sanitized errors")
    func parsesResponseFailure() {
        let events = feedLines([
            "event: response.failed",
            #"data: {"type":"response.failed","response":{"error":{"code":"rate_limit_exceeded","message":"Sensitive provider detail"}}}"#,
            "",
        ])

        guard case .error(let message) = events.first else {
            Issue.record("Expected error event")
            return
        }
        #expect(message.contains("rate_limit_exceeded"))
        #expect(!message.contains("Sensitive provider detail"))
    }

    @Test("Flush dispatches a truncated final event")
    func flushDispatchesPendingEvent() {
        var parser = SSEParser()
        #expect(parser.feed("event: response.completed") == nil)
        let event = parser.flush()

        guard case .responseCompleted = event else {
            Issue.record("Expected responseCompleted from flush")
            return
        }
    }

    @Test("Multi-line data payloads are joined")
    func joinsMultiLineData() {
        var parser = SSEParser()
        #expect(parser.feed("event: response.output_text.delta") == nil)
        #expect(parser.feed(#"data: {"type":"response.output_text.delta","#) == nil)
        #expect(parser.feed(#"data: "delta":"hi"}"#) == nil)
        let event = parser.feed("")

        guard case .textDelta(let text) = event else {
            Issue.record("Expected textDelta")
            return
        }
        #expect(text == "hi")
    }

    @Test("Malformed payloads are skipped without ending the stream")
    func skipsMalformedPayload() {
        let events = feedLines([
            "event: response.output_text.delta",
            "data: {not json",
            "",
            "event: response.output_text.delta",
            #"data: {"type":"response.output_text.delta","delta":"ok"}"#,
            "",
        ])

        guard events.count == 1, case .textDelta(let text) = events[0] else {
            Issue.record("Expected a single textDelta")
            return
        }
        #expect(text == "ok")
    }

    @Test("Unknown event types are ignored")
    func ignoresUnknownEvents() {
        let events = feedLines([
            "event: response.some_future_event",
            #"data: {"type":"response.some_future_event"}"#,
            "",
        ])

        #expect(events.isEmpty)
    }
}

@Suite("OpenAI response request encoding")
struct OpenAIResponseRequestEncodingTests {
    @Test("Encodes API field names and optional features")
    func encodesRequestFields() throws {
        let request = OpenAIResponseRequest(
            model: "gpt-5.6-terra",
            instructions: "sys",
            input: [OpenAIMessage(role: "user", content: "hi")],
            maxOutputTokens: 16000,
            stream: true,
            store: false,
            reasoning: .medium,
            text: .jsonSchema(.object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
            ]), name: "briefing")
        )

        let data = try JSONEncoder().encode(request)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["model"] as? String == "gpt-5.6-terra")
        #expect(json["instructions"] as? String == "sys")
        #expect(json["max_output_tokens"] as? Int == 16000)
        #expect(json["stream"] as? Bool == true)
        #expect(json["store"] as? Bool == false)

        let input = try #require(json["input"] as? [[String: Any]])
        #expect(input.first?["role"] as? String == "user")
        #expect(input.first?["content"] as? String == "hi")

        let reasoning = try #require(json["reasoning"] as? [String: Any])
        #expect(reasoning["effort"] as? String == "medium")

        let text = try #require(json["text"] as? [String: Any])
        let format = try #require(text["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect(format["name"] as? String == "briefing")
        #expect(format["strict"] as? Bool == true)
        let schema = try #require(format["schema"] as? [String: Any])
        #expect(schema["type"] as? String == "object")
        #expect(schema["additionalProperties"] as? Bool == false)
    }

    @Test("Omits optional fields when nil")
    func omitsNilFields() throws {
        let request = OpenAIResponseRequest(
            model: "gpt-5.6-terra",
            instructions: "sys",
            input: [],
            maxOutputTokens: 10,
            stream: false,
            store: false
        )

        let data = try JSONEncoder().encode(request)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["reasoning"] == nil)
        #expect(json["text"] == nil)
    }
}
