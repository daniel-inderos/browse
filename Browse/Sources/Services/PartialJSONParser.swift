import Foundation

/// Best-effort parser for JSON that may be truncated mid-stream.
///
/// OpenAI's structured outputs guarantee the *final* response is valid JSON,
/// but while streaming we only ever hold a prefix of it. This parser accepts
/// such prefixes and returns everything that is unambiguously present:
/// unterminated strings yield their partial content, incomplete trailing
/// object keys or values are dropped, and open arrays/objects are closed.
struct PartialJSONParser {
    static func parse(_ text: String) -> JSONValue? {
        var parser = PartialJSONParser(text: text)
        parser.skipWhitespace()
        return parser.parseValue()
    }

    private let characters: [Character]
    private var index: Int = 0

    private init(text: String) {
        self.characters = Array(text)
    }

    private var isAtEnd: Bool { index >= characters.count }

    private var current: Character? { isAtEnd ? nil : characters[index] }

    private mutating func advance() {
        index += 1
    }

    private mutating func skipWhitespace() {
        while let char = current, char == " " || char == "\n" || char == "\r" || char == "\t" {
            advance()
        }
    }

    private mutating func parseValue() -> JSONValue? {
        guard let char = current else { return nil }
        switch char {
        case "{":
            return parseObject()
        case "[":
            return parseArray()
        case "\"":
            return parseString().map { .string($0) }
        case "t", "f", "n":
            return parseLiteral()
        case "-", "0"..."9":
            return parseNumber()
        default:
            return nil
        }
    }

    private mutating func parseObject() -> JSONValue {
        advance() // consume {
        var members: [String: JSONValue] = [:]

        while true {
            skipWhitespace()
            if current == "}" {
                advance()
                break
            }
            // A key must be a *complete* string followed by a colon; otherwise
            // the trailing fragment is dropped.
            guard current == "\"" else { break }
            let keyStart = index
            guard let key = parseString(), keyWasTerminated(startedAt: keyStart) else { break }
            skipWhitespace()
            guard current == ":" else { break }
            advance()
            skipWhitespace()
            guard let value = parseValue() else { break }
            members[key] = value
            skipWhitespace()
            if current == "," {
                advance()
            } else if current == "}" {
                advance()
                break
            } else {
                break
            }
        }
        return .object(members)
    }

    private mutating func parseArray() -> JSONValue {
        advance() // consume [
        var values: [JSONValue] = []

        while true {
            skipWhitespace()
            if current == "]" {
                advance()
                break
            }
            guard let value = parseValue() else { break }
            values.append(value)
            skipWhitespace()
            if current == "," {
                advance()
            } else if current == "]" {
                advance()
                break
            } else {
                break
            }
        }
        return .array(values)
    }

    /// True when the string that began at `startedAt` ended with a closing
    /// quote rather than the end of input.
    private func keyWasTerminated(startedAt: Int) -> Bool {
        index > startedAt && index <= characters.count && characters[index - 1] == "\""
    }

    private mutating func parseString() -> String? {
        advance() // consume opening quote
        var result = ""

        while let char = current {
            if char == "\"" {
                advance()
                return result
            }
            if char == "\\" {
                guard let escaped = parseEscape() else {
                    // Truncated escape sequence — return what we decoded so far.
                    return result
                }
                result.append(escaped)
                continue
            }
            result.append(char)
            advance()
        }
        // Input ended mid-string: partial content is still useful for display.
        return result
    }

    private mutating func parseEscape() -> Character? {
        let escapeStart = index
        advance() // consume backslash
        guard let char = current else {
            index = escapeStart
            return nil
        }
        advance()
        switch char {
        case "\"": return "\""
        case "\\": return "\\"
        case "/": return "/"
        case "b": return "\u{08}"
        case "f": return "\u{0C}"
        case "n": return "\n"
        case "r": return "\r"
        case "t": return "\t"
        case "u":
            guard let code = parseHexCode() else {
                // Truncated unicode escape — stop cleanly at truncation.
                index = characters.count
                return nil
            }
            // Non-BMP characters arrive as UTF-16 surrogate pairs
            // (😀); combine them into a single scalar.
            if (0xD800...0xDBFF).contains(code) {
                guard current == "\\" else {
                    index = characters.count
                    return nil
                }
                advance()
                guard current == "u" else {
                    index = characters.count
                    return nil
                }
                advance()
                guard let low = parseHexCode(), (0xDC00...0xDFFF).contains(low) else {
                    index = characters.count
                    return nil
                }
                let combined = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                guard let scalar = Unicode.Scalar(combined) else { return nil }
                return Character(scalar)
            }
            guard let scalar = Unicode.Scalar(code) else { return nil }
            return Character(scalar)
        default:
            return nil
        }
    }

    private mutating func parseHexCode() -> UInt32? {
        var hex = ""
        for _ in 0..<4 {
            guard let digit = current, digit.isHexDigit else { return nil }
            hex.append(digit)
            advance()
        }
        return UInt32(hex, radix: 16)
    }

    private mutating func parseLiteral() -> JSONValue? {
        let literals: [(String, JSONValue)] = [
            ("true", .bool(true)),
            ("false", .bool(false)),
            ("null", .null),
        ]
        for (text, value) in literals {
            if matches(text) {
                index += text.count
                return value
            }
        }
        // A truncated literal (e.g. "tru" at end of input) yields nothing.
        index = characters.count
        return nil
    }

    private func matches(_ text: String) -> Bool {
        let end = index + text.count
        guard end <= characters.count else { return false }
        return String(characters[index..<end]) == text
    }

    private mutating func parseNumber() -> JSONValue? {
        let start = index
        while let char = current,
              char.isNumber || char == "-" || char == "+" || char == "." || char == "e" || char == "E" {
            advance()
        }
        let text = String(characters[start..<index])
        // If the number runs to the very end of input it may be truncated
        // (e.g. "12" of "123") — still parse it; briefing payloads carry no
        // load-bearing numbers, and a best-effort value beats dropping data.
        guard let value = Double(text) else { return nil }
        return .number(value)
    }
}
