import SwiftUI
import Combine

@MainActor
@Observable
final class IntentBarViewModel {
    var text: String = "" {
        didSet {
            scheduleClassification()
            scheduleAutocomplete()
        }
    }
    var liveClassification: IntentClassification?
    var autocompleteSuggestions: [String] = []
    var isExpanded: Bool = false

    private let classifier = IntentClassifier()
    private let autocompleteService: any SearchAutocompleteProviding
    private var isPrivateBrowsing: Bool
    private let isRemoteAutocompleteEnabled: @MainActor () -> Bool
    private var classificationTask: Task<Void, Never>?
    private var autocompleteTask: Task<Void, Never>?
    private var modeOverride: ModeOverride?

    init(
        autocompleteService: any SearchAutocompleteProviding = SearchAutocompleteService(),
        isPrivateBrowsing: Bool = false,
        isRemoteAutocompleteEnabled: @escaping @MainActor () -> Bool = {
            SearchAutocompleteSettings.remoteGoogleSuggestionsEnabled
        }
    ) {
        self.autocompleteService = autocompleteService
        self.isPrivateBrowsing = isPrivateBrowsing
        self.isRemoteAutocompleteEnabled = isRemoteAutocompleteEnabled
    }

    func setPrivateBrowsing(_ isPrivateBrowsing: Bool) {
        self.isPrivateBrowsing = isPrivateBrowsing
        scheduleAutocomplete()
    }

    func submit() -> IntentClassification {
        let classification = classifyForCurrentMode(text)
        text = ""
        modeOverride = nil
        liveClassification = nil
        return classification
    }

    func setURLDisplay(_ url: URL?) {
        modeOverride = nil
        if let url {
            text = url.absoluteString
            liveClassification = .open(url)
        }
    }

    @discardableResult
    func toggleSearchBriefMode(text currentText: String? = nil) -> Bool {
        if let currentText {
            text = currentText
        }

        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }
        guard case .open = classifier.classify(text) else {
            switch classifyForCurrentMode(text) {
            case .brief:
                modeOverride = .search
                liveClassification = .search(query: query)
            case .search:
                modeOverride = .brief
                liveClassification = .brief(query: query)
            case .open:
                return false
            }
            return true
        }

        return false
    }

    private func scheduleAutocomplete() {
        autocompleteTask?.cancel()

        let query = autocompleteQuery(from: text)
        guard let query else {
            autocompleteSuggestions = []
            return
        }

        autocompleteSuggestions = Self.localAutocompleteSuggestions(for: query)

        guard case .open = classifier.classify(query) else {
            guard let remoteQuery = remoteAutocompleteQuery(from: query) else { return }
            guard canRequestRemoteAutocomplete(for: remoteQuery) else { return }

            autocompleteTask = Task { [weak self, autocompleteService] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                let canRequest = await MainActor.run {
                    guard let self else { return false }
                    guard self.remoteAutocompleteQuery(from: self.text) == remoteQuery else { return false }
                    return self.canRequestRemoteAutocomplete(for: remoteQuery)
                }
                guard canRequest else { return }

                let suggestions = (try? await autocompleteService.suggestions(for: remoteQuery, limit: 5)) ?? []
                await MainActor.run {
                    guard let self else { return }
                    guard self.remoteAutocompleteQuery(from: self.text) == remoteQuery else { return }
                    guard self.canRequestRemoteAutocomplete(for: remoteQuery) else { return }
                    self.autocompleteSuggestions = Self.mergedAutocompleteSuggestions(
                        suggestions,
                        fallback: Self.localAutocompleteSuggestions(for: remoteQuery)
                    )
                }
            }
            return
        }

        autocompleteSuggestions = []
    }

    private func scheduleClassification() {
        classificationTask?.cancel()
        classificationTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            if text.isEmpty {
                modeOverride = nil
                liveClassification = nil
            } else {
                liveClassification = classifyForCurrentMode(text)
            }
        }
    }

    private func autocompleteQuery(from input: String) -> String? {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return nil }
        guard !query.contains("\n") else { return nil }
        return query
    }

    private func remoteAutocompleteQuery(from input: String) -> String? {
        guard let query = autocompleteQuery(from: input) else { return nil }
        guard query.count >= 4 else { return nil }
        guard case .search = classifier.classify(query) else { return nil }
        return query
    }

    private func canRequestRemoteAutocomplete(for query: String) -> Bool {
        guard remoteAutocompleteQuery(from: query) != nil else { return false }
        guard !isPrivateBrowsing else { return false }
        return isRemoteAutocompleteEnabled()
    }

    private static func localAutocompleteSuggestions(for query: String) -> [String] {
        [
            "\(query) news",
            "\(query) meaning",
            "\(query) tutorial",
            "\(query) examples",
            "\(query) near me"
        ]
    }

    private static func mergedAutocompleteSuggestions(_ suggestions: [String], fallback: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []

        for suggestion in suggestions + fallback {
            let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !trimmed.isEmpty else { continue }
            guard seen.insert(key).inserted else { continue }

            merged.append(trimmed)
            if merged.count >= 5 { break }
        }

        return merged
    }

    private func classifyForCurrentMode(_ input: String) -> IntentClassification {
        let classification = classifier.classify(input)
        guard let modeOverride else { return classification }

        switch classification {
        case .open:
            return classification
        case .brief(let query), .search(let query):
            switch modeOverride {
            case .brief:
                return .brief(query: query)
            case .search:
                return .search(query: query)
            }
        }
    }

    private enum ModeOverride {
        case brief
        case search
    }
}
