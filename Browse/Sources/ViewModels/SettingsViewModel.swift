import SwiftUI

@Observable
final class SettingsViewModel {
    var claudeAPIKey: String = ""
    var exaAPIKey: String = ""
    var claudeTestStatus: TestStatus = .idle
    var exaTestStatus: TestStatus = .idle

    enum TestStatus: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    private let keychain = KeychainService()

    init() {
        claudeAPIKey = keychain.read(.claudeAPIKey) ?? ""
        exaAPIKey = keychain.read(.exaAPIKey) ?? ""
    }

    func saveClaudeKey() {
        guard !claudeAPIKey.isEmpty else { return }
        try? keychain.save(claudeAPIKey, for: .claudeAPIKey)
    }

    func saveExaKey() {
        guard !exaAPIKey.isEmpty else { return }
        try? keychain.save(exaAPIKey, for: .exaAPIKey)
    }

    @MainActor
    func testClaudeConnection() async {
        claudeTestStatus = .testing
        let client = ClaudeAPIClient(getAPIKey: { [claudeAPIKey] in claudeAPIKey })
        do {
            let success = try await client.testConnection()
            claudeTestStatus = success ? .success : .failure("Unexpected response")
        } catch {
            claudeTestStatus = .failure(error.localizedDescription)
        }
    }

    @MainActor
    func testExaConnection() async {
        exaTestStatus = .testing
        let client = ExaAPIClient(getAPIKey: { [exaAPIKey] in exaAPIKey })
        do {
            let success = try await client.testConnection()
            exaTestStatus = success ? .success : .failure("Unexpected response")
        } catch {
            exaTestStatus = .failure(error.localizedDescription)
        }
    }
}
