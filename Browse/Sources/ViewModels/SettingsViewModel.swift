import SwiftUI
import WebKit

@Observable
@MainActor
final class SettingsViewModel {
    var openAIAPIKey: String = ""
    var exaAPIKey: String = ""
    var remoteGoogleSuggestionsEnabled: Bool = SearchAutocompleteSettings.remoteGoogleSuggestionsEnabled
    var openAITestStatus: TestStatus = .idle
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
        openAIAPIKey = apiKeyStore.read(.openAIAPIKey) ?? ""
        exaAPIKey = apiKeyStore.read(.exaAPIKey) ?? ""
    }

    func setOpenAIAPIKey(_ value: String) {
        openAIAPIKey = value
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
    func testOpenAIConnection() async {
        openAITestStatus = .testing
        let client = OpenAIAPIClient(getAPIKey: { [openAIAPIKey] in openAIAPIKey })
        do {
            let success = try await client.testConnection()
            openAITestStatus = success ? .success : .failure("Unexpected response")
        } catch {
            openAITestStatus = .failure(error.localizedDescription)
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
