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
}
