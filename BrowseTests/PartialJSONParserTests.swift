import Foundation
import Testing
@testable import Browse

@Suite("PartialJSONParser")
struct PartialJSONParserTests {
    @Test("Parses a complete object")
    func parsesCompleteObject() {
        let value = PartialJSONParser.parse(
            #"{"headline": "Hello", "count": 3, "ok": true, "missing": null, "tags": ["a", "b"]}"#
        )

        #expect(value?["headline"]?.stringValue == "Hello")
        #expect(value?["count"] == .number(3))
        #expect(value?["ok"] == .bool(true))
        #expect(value?["missing"] == .null)
        #expect(value?["tags"]?.arrayValue == [.string("a"), .string("b")])
    }

    @Test("Returns partial content for an unterminated string value")
    func parsesUnterminatedString() {
        let value = PartialJSONParser.parse(#"{"headline": "Passkeys are win"#)

        #expect(value?["headline"]?.stringValue == "Passkeys are win")
    }

    @Test("Drops an incomplete trailing key")
    func dropsIncompleteKey() {
        let value = PartialJSONParser.parse(#"{"headline": "Done", "tl"#)

        #expect(value?["headline"]?.stringValue == "Done")
        #expect(value?["tl"] == nil)
    }

    @Test("Drops a key whose value has not started")
    func dropsKeyWithoutValue() {
        let value = PartialJSONParser.parse(#"{"headline": "Done", "tldr": "#)

        #expect(value?["headline"]?.stringValue == "Done")
        #expect(value?["tldr"] == nil)
    }

    @Test("Closes an open array of objects")
    func parsesTruncatedArray() {
        let value = PartialJSONParser.parse(
            #"{"sections": [{"title": "One", "content": "Full"}, {"title": "Two", "content": "Part"#
        )

        let sections = value?["sections"]?.arrayValue
        #expect(sections?.count == 2)
        #expect(sections?[0]["title"]?.stringValue == "One")
        #expect(sections?[1]["content"]?.stringValue == "Part")
    }

    @Test("Decodes escape sequences")
    func decodesEscapes() {
        let value = PartialJSONParser.parse(#"{"text": "line\nquote \" slash \\ tab\t"}"#)

        #expect(value?["text"]?.stringValue == "line\nquote \" slash \\ tab\t")
    }

    @Test("Drops a truncated escape sequence but keeps prior content")
    func dropsTruncatedEscape() {
        let value = PartialJSONParser.parse(#"{"text": "abc\"#)

        #expect(value?["text"]?.stringValue == "abc")
    }

    @Test("Decodes unicode escapes including surrogate pairs")
    func decodesUnicodeEscapes() {
        let value = PartialJSONParser.parse("{\"text\": \"caf\\u00e9 \\ud83d\\ude00\"}")

        #expect(value?["text"]?.stringValue == "café 😀")
    }

    @Test("Keeps decoded prefix when a unicode escape is truncated")
    func dropsTruncatedUnicodeEscape() {
        let value = PartialJSONParser.parse(#"{"text": "abc\ud83d\ude"#)

        #expect(value?["text"]?.stringValue == "abc")
    }

    @Test("Drops a truncated literal")
    func dropsTruncatedLiteral() {
        let value = PartialJSONParser.parse(#"{"a": 1, "b": tru"#)

        #expect(value?["a"] == .number(1))
        #expect(value?["b"] == nil)
    }

    @Test("Parses negative and exponent numbers")
    func parsesNumbers() {
        let value = PartialJSONParser.parse(#"{"a": -1.5, "b": 2e3}"#)

        #expect(value?["a"] == .number(-1.5))
        #expect(value?["b"] == .number(2000))
    }

    @Test("Empty and whitespace input yields nil")
    func emptyInput() {
        #expect(PartialJSONParser.parse("") == nil)
        #expect(PartialJSONParser.parse("   \n") == nil)
    }

    @Test("Bare opening brace yields an empty object")
    func bareBrace() {
        #expect(PartialJSONParser.parse("{") == .object([:]))
    }
}
