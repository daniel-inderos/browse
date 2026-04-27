import SwiftUI
import WebKit

@Observable
@MainActor
final class SettingsViewModel {
    var claudeAPIKey: String = ""
    var exaAPIKey: String = ""
    var remoteGoogleSuggestionsEnabled: Bool = SearchAutocompleteSettings.remoteGoogleSuggestionsEnabled
    var claudeTestStatus: TestStatus = .idle
    var exaTestStatus: TestStatus = .idle
    var clearBrowsingDataStatus: ActionStatus = .idle
    var clearAIHistoryStatus: ActionStatus = .idle
    let apiKeyConfigurationSource = ".env or process environment"

    enum TestStatus: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    enum ActionStatus: Equatable {
        case idle
        case running
        case success(String)
        case failure(String)
    }

    private let apiKeyStore = APIKeyStore()
    private let persistenceStore = BrowserPersistenceStore()
    private var hasLoadedAPIKeys = false

    func loadAPIKeysIfNeeded() {
        guard !hasLoadedAPIKeys else { return }
        hasLoadedAPIKeys = true
        claudeAPIKey = apiKeyStore.read(.claudeAPIKey) ?? ""
        exaAPIKey = apiKeyStore.read(.exaAPIKey) ?? ""
    }

    func setClaudeAPIKey(_ value: String) {
        claudeAPIKey = value
    }

    func setExaAPIKey(_ value: String) {
        exaAPIKey = value
    }

    func setRemoteGoogleSuggestionsEnabled(_ value: Bool) {
        remoteGoogleSuggestionsEnabled = value
        SearchAutocompleteSettings.remoteGoogleSuggestionsEnabled = value
    }

    @MainActor
    func clearBrowsingData() async {
        clearBrowsingDataStatus = .running
        do {
            try persistenceStore.clearBrowsingData()
            await clearDefaultWebsiteData()
            NotificationCenter.default.post(name: .browseClearBrowsingDataRequested, object: nil)
            clearBrowsingDataStatus = .success("Browsing data cleared")
        } catch {
            clearBrowsingDataStatus = .failure(error.localizedDescription)
        }
    }

    @MainActor
    func clearAIHistory() {
        clearAIHistoryStatus = .running
        do {
            try persistenceStore.clearAIHistory()
            NotificationCenter.default.post(name: .browseClearAIHistoryRequested, object: nil)
            clearAIHistoryStatus = .success("AI history cleared")
        } catch {
            clearAIHistoryStatus = .failure(error.localizedDescription)
        }
    }

    private func clearDefaultWebsiteData() async {
        let store = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        await withCheckedContinuation { continuation in
            store.removeData(
                ofTypes: dataTypes,
                modifiedSince: .distantPast
            ) {
                continuation.resume()
            }
        }
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
