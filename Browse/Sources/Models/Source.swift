import Foundation

struct Source: Identifiable, Codable {
    let id: UUID
    let title: String
    let url: URL
    let snippet: String
    let faviconURL: URL?
    let imageURL: URL?
    let publishedDate: String?
    let author: String?

    init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        snippet: String,
        faviconURL: URL? = nil,
        imageURL: URL? = nil,
        publishedDate: String? = nil,
        author: String? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.snippet = snippet
        self.faviconURL = faviconURL
        self.imageURL = imageURL
        self.publishedDate = publishedDate
        self.author = author
    }
}
