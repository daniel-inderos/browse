import Foundation
import Testing
@testable import Browse

@MainActor
@Suite("IntentBarViewModel")
struct IntentBarViewModelTests {
    @Test("Shift tab toggles brief text to search")
    func shiftTabTogglesBriefTextToSearch() {
        let viewModel = IntentBarViewModel()
        viewModel.text = "what is rust?"

        #expect(viewModel.toggleSearchBriefMode())
        #expect(viewModel.liveClassification == .search(query: "what is rust?"))
        #expect(viewModel.submit() == .search(query: "what is rust?"))
    }

    @Test("Shift tab toggles search text to brief")
    func shiftTabTogglesSearchTextToBrief() {
        let viewModel = IntentBarViewModel()
        viewModel.text = "swift tutorial"

        #expect(viewModel.toggleSearchBriefMode())
        #expect(viewModel.liveClassification == .brief(query: "swift tutorial"))
        #expect(viewModel.submit() == .brief(query: "swift tutorial"))
    }

    @Test("Shift tab toggles back to automatic mode counterpart")
    func shiftTabTogglesBackToAutomaticModeCounterpart() {
        let viewModel = IntentBarViewModel()
        viewModel.text = "swift tutorial"

        #expect(viewModel.toggleSearchBriefMode())
        #expect(viewModel.liveClassification == .brief(query: "swift tutorial"))
        #expect(viewModel.toggleSearchBriefMode())
        #expect(viewModel.liveClassification == .search(query: "swift tutorial"))
    }

    @Test("Shift tab toggle uses current editor text")
    func shiftTabToggleUsesCurrentEditorText() {
        let viewModel = IntentBarViewModel()
        viewModel.text = "stale"

        #expect(viewModel.toggleSearchBriefMode(text: "why is the sky blue?"))
        #expect(viewModel.liveClassification == .search(query: "why is the sky blue?"))
        #expect(viewModel.submit() == .search(query: "why is the sky blue?"))
    }

    @Test("Shift tab toggle ignores URL input")
    func shiftTabToggleIgnoresURLInput() {
        let viewModel = IntentBarViewModel()
        viewModel.text = "https://apple.com"

        #expect(!viewModel.toggleSearchBriefMode())
        #expect(viewModel.submit() == .open(URL(string: "https://apple.com")!))
    }

    @Test("Autocomplete suggestions are available immediately for search text")
    func autocompleteSuggestionsAreAvailableImmediatelyForSearchText() {
        let viewModel = IntentBarViewModel()
        viewModel.text = "the amazing digital c"

        #expect(viewModel.autocompleteSuggestions == [
            "the amazing digital c news",
            "the amazing digital c meaning",
            "the amazing digital c tutorial",
            "the amazing digital c examples",
            "the amazing digital c near me"
        ])
    }

    @Test("Autocomplete suggestions ignore URL input")
    func autocompleteSuggestionsIgnoreURLInput() {
        let viewModel = IntentBarViewModel()
        viewModel.text = "https://apple.com"

        #expect(viewModel.autocompleteSuggestions.isEmpty)
    }

    @Test("Remote autocomplete is not requested when setting is disabled")
    func remoteAutocompleteIsNotRequestedWhenSettingIsDisabled() async throws {
        let service = RecordingAutocompleteService(suggestions: ["swift package manager"])
        let viewModel = IntentBarViewModel(
            autocompleteService: service,
            isRemoteAutocompleteEnabled: { false }
        )
        viewModel.text = "swift tutorial"

        try await Task.sleep(for: .milliseconds(450))

        #expect(await service.requestedQueries() == [])
        #expect(viewModel.autocompleteSuggestions == [
            "swift tutorial news",
            "swift tutorial meaning",
            "swift tutorial tutorial",
            "swift tutorial examples",
            "swift tutorial near me"
        ])
    }

    @Test("Remote autocomplete is requested for likely search input when enabled")
    func remoteAutocompleteIsRequestedForLikelySearchInputWhenEnabled() async throws {
        let service = RecordingAutocompleteService(suggestions: [
            "swift package manager",
            "swift concurrency"
        ])
        let viewModel = IntentBarViewModel(
            autocompleteService: service,
            isRemoteAutocompleteEnabled: { true }
        )
        viewModel.text = "swift tutorial"

        try await waitForRemoteAutocompleteSuggestions(
            in: viewModel,
            service: service,
            expectedQueries: ["swift tutorial"],
            expectedPrefix: [
                "swift package manager",
                "swift concurrency"
            ]
        )

        #expect(await service.requestedQueries() == ["swift tutorial"])
        #expect(Array(viewModel.autocompleteSuggestions.prefix(2)) == [
            "swift package manager",
            "swift concurrency"
        ])
    }

    @Test("Remote autocomplete skips private windows while local suggestions remain")
    func remoteAutocompleteSkipsPrivateWindowsWhileLocalSuggestionsRemain() async throws {
        let service = RecordingAutocompleteService(suggestions: ["swift package manager"])
        let viewModel = IntentBarViewModel(
            autocompleteService: service,
            isPrivateBrowsing: true,
            isRemoteAutocompleteEnabled: { true }
        )
        viewModel.text = "swift tutorial"

        try await Task.sleep(for: .milliseconds(450))

        #expect(await service.requestedQueries() == [])
        #expect(viewModel.autocompleteSuggestions == [
            "swift tutorial news",
            "swift tutorial meaning",
            "swift tutorial tutorial",
            "swift tutorial examples",
            "swift tutorial near me"
        ])
    }

    @Test("Remote autocomplete skips briefing-like natural language")
    func remoteAutocompleteSkipsBriefingLikeNaturalLanguage() async throws {
        let service = RecordingAutocompleteService(suggestions: ["what is swift"])
        let viewModel = IntentBarViewModel(
            autocompleteService: service,
            isRemoteAutocompleteEnabled: { true }
        )
        viewModel.text = "what is swift concurrency?"

        try await Task.sleep(for: .milliseconds(450))

        #expect(await service.requestedQueries() == [])
        #expect(!viewModel.autocompleteSuggestions.isEmpty)
    }

    @Test("Remote autocomplete waits for a longer search threshold")
    func remoteAutocompleteWaitsForLongerSearchThreshold() async throws {
        let service = RecordingAutocompleteService(suggestions: ["cat videos"])
        let viewModel = IntentBarViewModel(
            autocompleteService: service,
            isRemoteAutocompleteEnabled: { true }
        )
        viewModel.text = "cat"

        try await Task.sleep(for: .milliseconds(450))

        #expect(await service.requestedQueries() == [])
        #expect(viewModel.autocompleteSuggestions == [
            "cat news",
            "cat meaning",
            "cat tutorial",
            "cat examples",
            "cat near me"
        ])
    }

    private func waitForRemoteAutocompleteSuggestions(
        in viewModel: IntentBarViewModel,
        service: RecordingAutocompleteService,
        expectedQueries: [String],
        expectedPrefix: [String],
        timeout: Duration = .seconds(3)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let requestedQueries = await service.requestedQueries()
            let suggestionPrefix = Array(viewModel.autocompleteSuggestions.prefix(expectedPrefix.count))
            if requestedQueries == expectedQueries, suggestionPrefix == expectedPrefix {
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}

private actor RecordingAutocompleteService: SearchAutocompleteProviding {
    private var queries: [String] = []
    private let autocompleteSuggestions: [String]

    init(suggestions: [String]) {
        autocompleteSuggestions = suggestions
    }

    func suggestions(for query: String, limit: Int) async throws -> [String] {
        queries.append(query)
        return Array(autocompleteSuggestions.prefix(limit))
    }

    func requestedQueries() -> [String] {
        queries
    }
}
