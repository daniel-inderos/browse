import AppKit
import Foundation

actor FaviconService {
    static let shared = FaviconService()

    private var cache: [String: NSImage] = [:]
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    func favicon(for url: URL) async -> NSImage? {
        guard let host = url.host else { return nil }

        if let cached = cache[host] {
            return cached
        }

        if let existing = inFlight[host] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            let faviconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")!
            do {
                let (data, response) = try await URLSession.shared.data(from: faviconURL)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let image = NSImage(data: data) else {
                    return nil
                }
                cache[host] = image
                return image
            } catch {
                return nil
            }
        }

        inFlight[host] = task
        let result = await task.value
        inFlight[host] = nil
        return result
    }
}
