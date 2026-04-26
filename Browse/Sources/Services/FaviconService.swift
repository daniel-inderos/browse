import AppKit
import Foundation

actor FaviconService {
    static let shared = FaviconService()

    private var cache: [String: NSImage] = [:]
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private let privateSession = URLSession(configuration: .ephemeral)

    func favicon(for url: URL, isPrivateBrowsing: Bool = false) async -> NSImage? {
        guard let host = url.host else { return nil }

        if isPrivateBrowsing {
            return await fetchFavicon(for: host, session: privateSession)
        }

        if let cached = cache[host] {
            return cached
        }

        if let existing = inFlight[host] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            if let image = await self.fetchFavicon(for: host, session: .shared) {
                cache[host] = image
                return image
            }
            return nil
        }

        inFlight[host] = task
        let result = await task.value
        inFlight[host] = nil
        return result
    }

    private func fetchFavicon(for host: String, session: URLSession) async -> NSImage? {
        let faviconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")!
        var request = URLRequest(url: faviconURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            return NSImage(data: data)
        } catch {
            return nil
        }
    }
}
