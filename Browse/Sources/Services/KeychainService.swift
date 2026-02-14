import Foundation
@preconcurrency import KeychainAccess

struct KeychainService: @unchecked Sendable {
    private let keychain = Keychain(service: "com.browse.app")

    enum Key: String {
        case claudeAPIKey = "claude-api-key"
        case exaAPIKey = "exa-api-key"
    }

    func save(_ value: String, for key: Key) throws {
        try keychain.set(value, key: key.rawValue)
    }

    func read(_ key: Key) -> String? {
        try? keychain.get(key.rawValue)
    }

    func delete(_ key: Key) throws {
        try keychain.remove(key.rawValue)
    }
}
