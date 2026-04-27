import Foundation

struct FaviconFetchRequest: Equatable {
    let cacheKey: String
    let url: URL
}

enum FaviconFetchPolicy {
    case standard
    case firstPartyOnly
}

actor FaviconService {
    static let shared = FaviconService()

    private var cache: [String: Data] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private let privateSession = URLSession(configuration: .ephemeral)

    func faviconData(
        for url: URL,
        isPrivateBrowsing: Bool = false,
        allowsGoogleS2Fallback: Bool = true
    ) async -> Data? {
        let policy: FaviconFetchPolicy = isPrivateBrowsing && !allowsGoogleS2Fallback
            ? .firstPartyOnly
            : .standard
        guard let request = Self.fetchRequest(for: url, policy: policy) else { return nil }

        if isPrivateBrowsing {
            return await fetchFaviconData(request, session: privateSession)
        }

        if let cached = cache[request.cacheKey] {
            return cached
        }

        if let existing = inFlight[request.cacheKey] {
            return await existing.value
        }

        let task = Task<Data?, Never> {
            await self.fetchFaviconData(request, session: .shared)
        }

        inFlight[request.cacheKey] = task
        let result = await task.value
        if let result {
            cache[request.cacheKey] = result
        }
        inFlight[request.cacheKey] = nil
        return result
    }

    static func fetchRequest(
        for url: URL,
        size: Int = 64,
        policy: FaviconFetchPolicy = .standard
    ) -> FaviconFetchRequest? {
        if let targetHost = googleS2TargetHost(from: url) {
            switch policy {
            case .standard:
                return googleS2FetchRequest(for: targetHost, size: size)
            case .firstPartyOnly:
                return firstPartyFaviconFetchRequest(for: targetHost)
            }
        }

        if isLikelyDirectFaviconURL(url) {
            return FaviconFetchRequest(
                cacheKey: url.absoluteString.lowercased(),
                url: url
            )
        }

        guard let host = normalizedHost(from: url) else { return nil }
        switch policy {
        case .standard:
            return googleS2FetchRequest(for: host, size: size)
        case .firstPartyOnly:
            return firstPartyFaviconFetchRequest(for: url)
        }
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

    private static func firstPartyFaviconFetchRequest(for url: URL) -> FaviconFetchRequest? {
        guard let host = url.host?.lowercased() else { return nil }
        let scheme = (url.scheme == "http" || url.scheme == "https") ? url.scheme : "https"
        return firstPartyFaviconFetchRequest(for: host, scheme: scheme)
    }

    private static func firstPartyFaviconFetchRequest(
        for host: String,
        scheme: String? = "https"
    ) -> FaviconFetchRequest? {
        var components = URLComponents()
        components.scheme = scheme ?? "https"
        components.host = host
        components.path = "/favicon.ico"

        guard let url = components.url else { return nil }
        return FaviconFetchRequest(
            cacheKey: url.absoluteString.lowercased(),
            url: url
        )
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

    private func fetchFaviconData(_ faviconRequest: FaviconFetchRequest, session: URLSession) async -> Data? {
        var request = URLRequest(url: faviconRequest.url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }
}
