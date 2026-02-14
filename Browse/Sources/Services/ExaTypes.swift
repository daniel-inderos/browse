import Foundation

// MARK: - Request

struct ExaSearchRequest: Encodable {
    let query: String
    let type: String
    let numResults: Int
    let contents: ExaContents?

    enum CodingKeys: String, CodingKey {
        case query, type, contents
        case numResults = "num_results"
    }
}

struct ExaContents: Encodable {
    let text: ExaTextConfig?
    let highlights: ExaHighlightsConfig?

    init(text: ExaTextConfig? = nil, highlights: ExaHighlightsConfig? = nil) {
        self.text = text
        self.highlights = highlights
    }
}

struct ExaTextConfig: Encodable {
    let maxCharacters: Int

    enum CodingKeys: String, CodingKey {
        case maxCharacters = "max_characters"
    }
}

struct ExaHighlightsConfig: Encodable {
    let numSentences: Int
    let highlightsPerUrl: Int

    enum CodingKeys: String, CodingKey {
        case numSentences = "num_sentences"
        case highlightsPerUrl = "highlights_per_url"
    }
}

// MARK: - Response

struct ExaSearchResponse: Decodable {
    let requestId: String
    let results: [ExaSearchResult]

    enum CodingKeys: String, CodingKey {
        case requestId = "requestId"
        case results
    }
}

struct ExaSearchResult: Decodable {
    let title: String
    let url: String
    let publishedDate: String?
    let author: String?
    let text: String?
    let highlights: [String]?
    let highlightScores: [Double]?
    let favicon: String?
    let image: String?

    enum CodingKeys: String, CodingKey {
        case title, url, author, text, highlights, favicon, image
        case publishedDate = "publishedDate"
        case highlightScores = "highlightScores"
    }
}
