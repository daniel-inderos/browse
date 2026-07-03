import Foundation
import Testing
@testable import Browse

@Suite("SSEParser")
struct ClaudeStreamParserTests {
    private func feedLines(_ lines: [String]) -> [ClaudeStreamEvent] {
        var parser = SSEParser()
        var events: [ClaudeStreamEvent] = []
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
            "event: message_start",
            #"data: {"type":"message_start","message":{"id":"msg_01","model":"claude-opus-4-8"}}"#,
            "",
            "event: content_block_start",
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            "",
            "event: content_block_delta",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
            "",
            "event: content_block_delta",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}"#,
            "",
            "event: content_block_stop",
            #"data: {"type":"content_block_stop","index":0}"#,
            "",
            "event: message_delta",
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":12}}"#,
            "",
            "event: message_stop",
            #"data: {"type":"message_stop"}"#,
            "",
        ])

        guard events.count == 7 else {
            Issue.record("Expected 7 events, got \(events.count)")
            return
        }
        guard case .messageStart(let id, let model) = events[0] else {
            Issue.record("Expected messageStart")
            return
        }
        #expect(id == "msg_01")
        #expect(model == "claude-opus-4-8")
        guard case .textDelta(let first) = events[2], case .textDelta(let second) = events[3] else {
            Issue.record("Expected text deltas")
            return
        }
        #expect(first + second == "Hello world")
        guard case .messageDelta(let stopReason) = events[5] else {
            Issue.record("Expected messageDelta")
            return
        }
        #expect(stopReason == "end_turn")
        guard case .messageStop = events[6] else {
            Issue.record("Expected messageStop")
            return
        }
    }

    @Test("Thinking deltas produce no event")
    func ignoresThinkingDeltas() {
        let events = feedLines([
            "event: content_block_delta",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hmm"}}"#,
            "",
        ])

        #expect(events.isEmpty)
    }

    @Test("Ping events pass through")
    func parsesPing() {
        let events = feedLines([
            "event: ping",
            #"data: {"type":"ping"}"#,
            "",
        ])

        guard case .ping = events.first else {
            Issue.record("Expected ping")
            return
        }
    }

    @Test("Error events are sanitized")
    func sanitizesErrorEvents() {
        let events = feedLines([
            "event: error",
            #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
            "",
        ])

        guard case .error(let message) = events.first else {
            Issue.record("Expected error event")
            return
        }
        #expect(message.contains("overloaded_error"))
        #expect(!message.contains("Overloaded"))
    }

    @Test("Suspicious error types are replaced with unknown")
    func replacesSuspiciousErrorType() {
        let events = feedLines([
            "event: error",
            #"data: {"type":"error","error":{"type":"weird type; drop table","message":"x"}}"#,
            "",
        ])

        guard case .error(let message) = events.first else {
            Issue.record("Expected error event")
            return
        }
        #expect(message.contains("unknown"))
        #expect(!message.contains("drop table"))
    }

    @Test("Flush dispatches a truncated final event")
    func flushDispatchesPendingEvent() {
        var parser = SSEParser()
        #expect(parser.feed("event: message_stop") == nil)
        // Stream cut off before the terminating blank line.
        let event = parser.flush()

        guard case .messageStop = event else {
            Issue.record("Expected messageStop from flush")
            return
        }
    }

    @Test("Multi-line data payloads are joined")
    func joinsMultiLineData() {
        var parser = SSEParser()
        #expect(parser.feed("event: content_block_delta") == nil)
        #expect(parser.feed(#"data: {"type":"content_block_delta","index":0,"#) == nil)
        #expect(parser.feed(#"data: "delta":{"type":"text_delta","text":"hi"}}"#) == nil)
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
            "event: content_block_delta",
            "data: {not json",
            "",
            "event: content_block_delta",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"ok"}}"#,
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
            "event: some_future_event",
            #"data: {"type":"some_future_event"}"#,
            "",
        ])

        #expect(events.isEmpty)
    }
}

@Suite("ClaudeMessageRequest encoding")
struct ClaudeMessageRequestEncodingTests {
    @Test("Encodes API field names and optional features")
    func encodesRequestFields() throws {
        let request = ClaudeMessageRequest(
            model: "claude-opus-4-8",
            system: "sys",
            messages: [ClaudeMessage(role: "user", content: "hi")],
            maxTokens: 16000,
            stream: true,
            thinking: .adaptive,
            outputConfig: .jsonSchema(.object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
            ])),
            cacheControl: .ephemeral
        )

        let data = try JSONEncoder().encode(request)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["model"] as? String == "claude-opus-4-8")
        #expect(json["max_tokens"] as? Int == 16000)
        #expect(json["stream"] as? Bool == true)

        let thinking = try #require(json["thinking"] as? [String: Any])
        #expect(thinking["type"] as? String == "adaptive")

        let cacheControl = try #require(json["cache_control"] as? [String: Any])
        #expect(cacheControl["type"] as? String == "ephemeral")

        let outputConfig = try #require(json["output_config"] as? [String: Any])
        let format = try #require(outputConfig["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["schema"] as? [String: Any])
        #expect(schema["type"] as? String == "object")
        #expect(schema["additionalProperties"] as? Bool == false)
    }

    @Test("Omits optional fields when nil")
    func omitsNilFields() throws {
        let request = ClaudeMessageRequest(
            model: "claude-opus-4-8",
            system: "sys",
            messages: [],
            maxTokens: 10,
            stream: false
        )

        let data = try JSONEncoder().encode(request)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["thinking"] == nil)
        #expect(json["output_config"] == nil)
        #expect(json["cache_control"] == nil)
    }
}
