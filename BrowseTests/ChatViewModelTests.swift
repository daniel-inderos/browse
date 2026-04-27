import Foundation
import Testing
@testable import Browse

@MainActor
@Suite("ChatViewModel")
struct ChatViewModelTests {
    @Test("Page context is included by default")
    func pageContextIsIncludedByDefault() throws {
        let viewModel = makeViewModel()
        let url = try #require(URL(string: "https://example.com/article"))

        viewModel.primePageContext(url: url, title: "Example Article")

        #expect(viewModel.pageContextLabel == "Example Article")
        #expect(viewModel.buildSystemPrompt().contains("Current page URL: https://example.com/article"))
        #expect(viewModel.buildSystemPrompt().contains("Page title: Example Article"))
    }

    @Test("Removing page context excludes page metadata from model prompt")
    func removingPageContextExcludesPageMetadataFromModelPrompt() throws {
        let viewModel = makeViewModel()
        let url = try #require(URL(string: "https://example.com/private-note"))

        viewModel.primePageContext(url: url, title: "Private Note")
        viewModel.removePageContextFromModel()

        let prompt = viewModel.buildSystemPrompt()

        #expect(viewModel.pageContextLabel == nil)
        #expect(!prompt.contains("https://example.com/private-note"))
        #expect(!prompt.contains("Private Note"))
        #expect(prompt.contains("No current page context is attached"))
    }

    private func makeViewModel() -> ChatViewModel {
        ChatViewModel(claudeClient: ClaudeAPIClient(getAPIKey: { nil }))
    }
}
