import Foundation

extension URL {
    var displayHost: String {
        host ?? absoluteString
    }

    var displayString: String {
        var str = absoluteString
        // Remove trailing slash
        if str.hasSuffix("/") && str.count > 1 {
            str = String(str.dropLast())
        }
        // Remove scheme for display
        if let range = str.range(of: "://") {
            str = String(str[range.upperBound...])
        }
        return str
    }

    /// Stable key for page-scoped chat sessions.
    /// Ignores URL fragments so in-page anchor navigation reuses one chat.
    var chatSessionKey: String {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return absoluteString
        }

        components.fragment = nil
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()

        if let scheme = components.scheme,
           let port = components.port,
           (scheme == "http" && port == 80) || (scheme == "https" && port == 443) {
            components.port = nil
        }

        return components.string ?? absoluteString
    }
}
