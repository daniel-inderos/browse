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

    @Test("Mentioned tab context is included in model prompt")
    func mentionedTabContextIsIncludedInModelPrompt() throws {
        let viewModel = makeViewModel()
        let url = try #require(URL(string: "https://example.com/reference"))

        viewModel.addMentionedTabContext(ChatMentionedTabContext(
            id: UUID(),
            title: "Reference Tab",
            url: url,
            content: "Reference content"
        ))

        let prompt = viewModel.buildSystemPrompt()

        #expect(prompt.contains("Mentioned tab contexts"))
        #expect(prompt.contains("Tab title: Reference Tab"))
        #expect(prompt.contains("URL: https://example.com/reference"))
        #expect(prompt.contains("Reference content"))
    }

    @Test("Removing mentioned tab context excludes it from model prompt")
    func removingMentionedTabContextExcludesItFromModelPrompt() throws {
        let viewModel = makeViewModel()
        let tabID = UUID()

        viewModel.addMentionedTabContext(ChatMentionedTabContext(
            id: tabID,
            title: "Reference Tab",
            url: nil,
            content: "Reference content"
        ))
        viewModel.removeMentionedTabContext(id: tabID)

        let prompt = viewModel.buildSystemPrompt()

        #expect(!prompt.contains("Reference Tab"))
        #expect(!prompt.contains("Reference content"))
    }

    private func makeViewModel() -> ChatViewModel {
        ChatViewModel(openAIClient: OpenAIAPIClient(getAPIKey: { nil }))
    }
}
