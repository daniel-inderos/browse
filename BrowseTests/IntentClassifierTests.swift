import Foundation
import Testing
@testable import Browse

@Suite("IntentClassifier")
struct IntentClassifierTests {
    let classifier = IntentClassifier()

    @Test("URLs with scheme are classified as open")
    func urlsWithScheme() {
        let result = classifier.classify("https://apple.com")
        #expect(result == .open(URL(string: "https://apple.com")!))
    }

    @Test("Domain-like inputs are classified as open")
    func domainLike() {
        let result = classifier.classify("apple.com")
        #expect(result == .open(URL(string: "https://apple.com")!))
    }

    @Test("Domain with path is classified as open")
    func domainWithPath() {
        let result = classifier.classify("github.com/user/repo")
        #expect(result == .open(URL(string: "https://github.com/user/repo")!))
    }

    @Test("Question with question mark is classified as brief")
    func questionMark() {
        let result = classifier.classify("what is rust?")
        #expect(result == .brief(query: "what is rust?"))
    }

    @Test("Question prefix is classified as brief")
    func questionPrefix() {
        let result = classifier.classify("how do monads work")
        #expect(result == .brief(query: "how do monads work"))
    }

    @Test("Explain prefix is classified as brief")
    func explainPrefix() {
        let result = classifier.classify("explain quantum computing")
        #expect(result == .brief(query: "explain quantum computing"))
    }

    @Test("Compare prefix is classified as brief")
    func comparePrefix() {
        let result = classifier.classify("compare react and vue")
        #expect(result == .brief(query: "compare react and vue"))
    }

    @Test("Long natural language is classified as brief")
    func longNaturalLanguage() {
        let result = classifier.classify("best restaurants in SF for a date night with vegetarian options")
        #expect(result == .brief(query: "best restaurants in SF for a date night with vegetarian options"))
    }

    @Test("Short phrase is classified as search")
    func shortPhrase() {
        let result = classifier.classify("swift tutorial")
        #expect(result == .search(query: "swift tutorial"))
    }

    @Test("Empty input")
    func emptyInput() {
        let result = classifier.classify("")
        #expect(result == .search(query: ""))
    }

    @Test("localhost is classified as open")
    func localhost() {
        let result = classifier.classify("localhost:3000")
        #expect(result == .open(URL(string: "http://localhost:3000")!))
    }
}
