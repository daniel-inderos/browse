import Foundation

enum BriefingCitationResolver {
    static func sourceURL(for citationURL: URL, sources: [Source]) -> URL? {
        guard citationURL.scheme == "cite" else { return nil }
        guard let citationNumber = citationNumber(from: citationURL) else { return nil }
        guard sources.indices.contains(citationNumber - 1) else { return nil }
        return sources[citationNumber - 1].url
    }

    private static func citationNumber(from url: URL) -> Int? {
        let candidates: [String?] = [
            url.host,
            url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            url.absoluteString
                .replacingOccurrences(of: "cite://", with: "")
                .replacingOccurrences(of: "cite:", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/")),
        ]

        return candidates.lazy.compactMap { candidate in
            guard let candidate, !candidate.isEmpty else { return nil }
            return Int(candidate)
        }.first
    }
}
