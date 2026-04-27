import Foundation

enum SearchAutocompleteSettings {
    private static let remoteGoogleSuggestionsEnabledKey = "remoteGoogleSearchAutocompleteEnabled"

    static var remoteGoogleSuggestionsEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: remoteGoogleSuggestionsEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: remoteGoogleSuggestionsEnabledKey)
        }
    }
}
