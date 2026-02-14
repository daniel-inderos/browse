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
}
