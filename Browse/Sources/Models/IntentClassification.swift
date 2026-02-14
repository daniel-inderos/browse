import Foundation

enum IntentClassification: Equatable {
    case open(URL)
    case brief(query: String)
    case search(query: String)

    var label: String {
        switch self {
        case .open: "Open"
        case .brief: "Brief"
        case .search: "Search"
        }
    }

    var color: String {
        switch self {
        case .open: "green"
        case .brief: "blue"
        case .search: "gray"
        }
    }
}
