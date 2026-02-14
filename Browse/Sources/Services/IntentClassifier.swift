import Foundation

struct IntentClassifier {
    private static let questionPrefixes = [
        "what", "how", "why", "when", "where", "who", "which",
        "explain", "compare", "summarize", "tell me", "describe",
        "is there", "are there", "can you", "should i", "what's",
        "what are", "how do", "how does", "how to", "why do",
        "why does", "what is"
    ]

    func classify(_ input: String) -> IntentClassification {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .search(query: "") }

        // 1. Has URL scheme (http:// or https://)
        if let url = URL(string: trimmed),
           let scheme = url.scheme,
           (scheme == "http" || scheme == "https"),
           url.host != nil {
            return .open(url)
        }

        // 2. Domain-like pattern (e.g., "apple.com", "github.com/user/repo")
        if isDomainLike(trimmed) {
            let urlString = "https://\(trimmed)"
            if let url = URL(string: urlString) {
                return .open(url)
            }
        }

        // 3. localhost with port
        if trimmed.hasPrefix("localhost") {
            let urlString = "http://\(trimmed)"
            if let url = URL(string: urlString) {
                return .open(url)
            }
        }

        // 4. IP address pattern
        if isIPAddress(trimmed) {
            let urlString = "http://\(trimmed)"
            if let url = URL(string: urlString) {
                return .open(url)
            }
        }

        // 5. Question or research intent
        let lower = trimmed.lowercased()
        if lower.hasSuffix("?") {
            return .brief(query: trimmed)
        }

        for prefix in Self.questionPrefixes {
            if lower.hasPrefix(prefix + " ") || lower == prefix {
                return .brief(query: trimmed)
            }
        }

        // 6. Long natural language (5+ words) → likely a question
        let wordCount = trimmed.split(separator: " ").count
        if wordCount >= 5 {
            return .brief(query: trimmed)
        }

        // 7. Short phrase → search (which we default to brief)
        return .search(query: trimmed)
    }

    private func isDomainLike(_ input: String) -> Bool {
        let parts = input.split(separator: "/", maxSplits: 1)
        guard let domain = parts.first else { return false }
        let domainStr = String(domain)

        // Must contain at least one dot
        guard domainStr.contains(".") else { return false }

        // Must not contain spaces
        guard !domainStr.contains(" ") else { return false }

        // Domain parts should be alphanumeric + hyphens
        let domainParts = domainStr.split(separator: ".")
        guard domainParts.count >= 2 else { return false }

        // TLD should be 2-10 chars, all letters
        guard let tld = domainParts.last,
              tld.count >= 2, tld.count <= 10,
              tld.allSatisfy({ $0.isLetter }) else { return false }

        return true
    }

    private func isIPAddress(_ input: String) -> Bool {
        let parts = input.split(separator: ":")
        let host = String(parts.first ?? "")
        let octets = host.split(separator: ".")
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { octet in
            guard let num = Int(octet) else { return false }
            return num >= 0 && num <= 255
        }
    }
}
