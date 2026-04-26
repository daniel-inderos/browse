import AppKit
import Foundation

struct FaviconFetchRequest: Equatable {
    let cacheKey: String
    let url: URL
}

actor FaviconService {
    static let shared = FaviconService()

    private var cache: [String: NSImage] = [:]
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private let privateSession = URLSession(configuration: .ephemeral)

    func favicon(for url: URL, isPrivateBrowsing: Bool = false) async -> NSImage? {
        guard let request = Self.fetchRequest(for: url) else { return nil }

        if isPrivateBrowsing {
            return await fetchFavicon(request, session: privateSession)
        }

        if let cached = cache[request.cacheKey] {
            return cached
        }

        if let existing = inFlight[request.cacheKey] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            if let image = await self.fetchFavicon(request, session: .shared) {
                cache[request.cacheKey] = image
                return image
            }
            return nil
        }

        inFlight[request.cacheKey] = task
        let result = await task.value
        inFlight[request.cacheKey] = nil
        return result
    }

    static func fetchRequest(for url: URL, size: Int = 64) -> FaviconFetchRequest? {
        if let targetHost = googleS2TargetHost(from: url) {
            return googleS2FetchRequest(for: targetHost, size: size)
        }

        if isLikelyDirectFaviconURL(url) {
            return FaviconFetchRequest(
                cacheKey: url.absoluteString.lowercased(),
                url: url
            )
        }

        guard let host = normalizedHost(from: url) else { return nil }
        return googleS2FetchRequest(for: host, size: size)
    }

    private static func googleS2FetchRequest(for host: String, size: Int) -> FaviconFetchRequest? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/s2/favicons"
        components.queryItems = [
            URLQueryItem(name: "domain", value: host),
            URLQueryItem(name: "sz", value: String(size)),
        ]

        guard let url = components.url else { return nil }
        return FaviconFetchRequest(cacheKey: host, url: url)
    }

    private static func googleS2TargetHost(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              host == "google.com" || host.hasSuffix(".google.com"),
              url.path == "/s2/favicons",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        for queryName in ["domain", "domain_url"] {
            guard let value = components.queryItems?.first(where: { $0.name == queryName })?.value,
                  let targetHost = normalizedHost(from: value) else {
                continue
            }
            return targetHost
        }

        return nil
    }

    private static func normalizedHost(from url: URL) -> String? {
        normalizedHost(from: url.host)
    }

    private static func normalizedHost(from value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        if let url = URL(string: value), let host = url.host {
            value = host
        } else if let url = URL(string: "https://\(value)"), let host = url.host {
            value = host
        }

        value = value.lowercased()
        if value.hasPrefix("www.") {
            value.removeFirst(4)
        }
        return value.isEmpty ? nil : value
    }

    private static func isLikelyDirectFaviconURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        let lastPathComponent = url.lastPathComponent.lowercased()
        let imageExtensions: Set<String> = ["ico", "png", "jpg", "jpeg", "svg", "webp"]

        if lastPathComponent.contains("favicon") || path.contains("/favicon") {
            return true
        }

        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    private func fetchFavicon(_ faviconRequest: FaviconFetchRequest, session: URLSession) async -> NSImage? {
        var request = URLRequest(url: faviconRequest.url)
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
