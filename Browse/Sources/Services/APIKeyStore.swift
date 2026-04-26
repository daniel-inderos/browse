import Foundation
import LocalAuthentication
import Security

struct APIKeyStore: @unchecked Sendable {
    private final class Store: @unchecked Sendable {
        enum Entry {
            case missing
            case value(String)
        }

        private let service = "com.browse.app.api-keys.v2"
        private let legacyService = "com.browse.app"
        private let lock = NSLock()
        private var cache: [Key: Entry] = [:]

        func read(_ key: Key) -> String? {
            lock.lock()
            defer { lock.unlock() }

            if let cachedEntry = cache[key] {
                switch cachedEntry {
                case .missing:
                    return nil
                case .value(let value):
                    return value
                }
            }

            let value = readKeychainValue(for: key, service: service)
                ?? migrateLegacyValueIfAvailable(for: key)
            cache[key] = value.map(Entry.value) ?? .missing
            return value
        }

        func save(_ value: String, for key: Key) throws {
            lock.lock()
            defer { lock.unlock() }

            try saveKeychainValue(value, for: key, service: service)
            cache[key] = .value(value)
        }

        func delete(_ key: Key) throws {
            lock.lock()
            defer { lock.unlock() }

            try deleteKeychainValue(for: key, service: service)
            try deleteKeychainValue(for: key, service: legacyService)
            cache[key] = .missing
        }

        private func migrateLegacyValueIfAvailable(for key: Key) -> String? {
            guard let value = readKeychainValue(for: key, service: legacyService) else {
                return nil
            }

            try? saveKeychainValue(value, for: key, service: service)
            try? deleteKeychainValue(for: key, service: legacyService)
            return value
        }

        private func baseQuery(for key: Key, service: String) -> [CFString: Any] {
            let context = LAContext()
            context.interactionNotAllowed = true

            return [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: key.rawValue,
                kSecUseAuthenticationContext: context,
            ]
        }

        private func readKeychainValue(for key: Key, service: String) -> String? {
            var query = baseQuery(for: key, service: service)
            query[kSecMatchLimit] = kSecMatchLimitOne
            query[kSecReturnData] = true

            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess,
                  let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                return nil
            }
            return value
        }

        private func saveKeychainValue(_ value: String, for key: Key, service: String) throws {
            let data = Data(value.utf8)
            let updateQuery = baseQuery(for: key, service: service)
            let updateAttributes: [CFString: Any] = [
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]

            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
            switch updateStatus {
            case errSecSuccess:
                return
            case errSecItemNotFound:
                var addQuery = baseQuery(for: key, service: service)
                addQuery[kSecValueData] = data
                addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
                guard addStatus == errSecSuccess else {
                    throw error(status: addStatus, operation: "save")
                }
            default:
                throw error(status: updateStatus, operation: "save")
            }
        }

        private func deleteKeychainValue(for key: Key, service: String) throws {
            let status = SecItemDelete(baseQuery(for: key, service: service) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw error(status: status, operation: "delete")
            }
        }

        private func error(status: OSStatus, operation: String) -> NSError {
            NSError(
                domain: "BrowseAPIKeyStore",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Could not \(operation) API key. Security status: \(status)."]
            )
        }
    }

    private static let store = Store()

    enum Key: String {
        case claudeAPIKey = "claude-api-key"
        case exaAPIKey = "exa-api-key"
    }

    func save(_ value: String, for key: Key) throws {
        try Self.store.save(value, for: key)
    }

    func read(_ key: Key) -> String? {
        Self.store.read(key)
    }

    func delete(_ key: Key) throws {
        try Self.store.delete(key)
    }
}
