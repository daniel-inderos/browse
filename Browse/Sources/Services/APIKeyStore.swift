import Foundation

struct APIKeyStore: @unchecked Sendable {
    private final class Store: @unchecked Sendable {
        func read(_ key: Key) -> String? {
            let values = DotEnvLoader.load()
            return key.environmentNames.lazy
                .compactMap { values[$0]?.nonEmpty }
                .first
        }
    }

    private struct DotEnvLoader {
        static func load(
            environment: [String: String] = ProcessInfo.processInfo.environment,
            fileManager: FileManager = .default,
            sourceFilePath: String = #filePath
        ) -> [String: String] {
            var values = loadDotEnv(fileManager: fileManager, sourceFilePath: sourceFilePath)
            for (key, value) in environment {
                values[key] = value
            }
            return values
        }

        private static func loadDotEnv(fileManager: FileManager, sourceFilePath: String) -> [String: String] {
            guard let envURL = findDotEnv(fileManager: fileManager, sourceFilePath: sourceFilePath),
                  let content = try? String(contentsOf: envURL, encoding: .utf8) else {
                return [:]
            }
            return parse(content)
        }

        private static func findDotEnv(fileManager: FileManager, sourceFilePath: String) -> URL? {
            let startURLs = [
                URL(fileURLWithPath: fileManager.currentDirectoryPath),
                URL(fileURLWithPath: CommandLine.arguments.first ?? fileManager.currentDirectoryPath)
                    .deletingLastPathComponent(),
                Bundle.main.bundleURL,
                URL(fileURLWithPath: sourceFilePath).deletingLastPathComponent(),
            ]

            for startURL in startURLs {
                if let envURL = findDotEnv(ascendingFrom: startURL, fileManager: fileManager) {
                    return envURL
                }
            }
            return nil
        }

        private static func findDotEnv(ascendingFrom startURL: URL, fileManager: FileManager) -> URL? {
            var directory = startURL.standardizedFileURL
            while true {
                let envURL = directory.appendingPathComponent(".env")
                if fileManager.fileExists(atPath: envURL.path) {
                    return envURL
                }

                let parent = directory.deletingLastPathComponent()
                guard parent.path != directory.path else {
                    return nil
                }
                directory = parent
            }
        }

        private static func parse(_ content: String) -> [String: String] {
            var values: [String: String] = [:]
            for rawLine in content.components(separatedBy: .newlines) {
                guard let entry = parseLine(rawLine) else { continue }
                values[entry.key] = entry.value
            }
            return values
        }

        private static func parseLine(_ rawLine: String) -> (key: String, value: String)? {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else {
                return nil
            }

            if line.hasPrefix("export ") {
                line.removeFirst("export ".count)
                line = line.trimmingCharacters(in: .whitespaces)
            }

            guard let separator = line.firstIndex(of: "=") else {
                return nil
            }

            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let rawValue = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                return nil
            }

            return (String(key), parseValue(String(rawValue)))
        }

        private static func parseValue(_ rawValue: String) -> String {
            guard rawValue.count >= 2 else {
                return rawValue
            }

            let first = rawValue.first
            let last = rawValue.last
            if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                let start = rawValue.index(after: rawValue.startIndex)
                let end = rawValue.index(before: rawValue.endIndex)
                return String(rawValue[start..<end])
            }

            guard let commentStart = rawValue.range(of: " #")?.lowerBound else {
                return rawValue
            }
            return rawValue[..<commentStart].trimmingCharacters(in: .whitespaces)
        }
    }

    private static let store = Store()

    enum Key {
        case claudeAPIKey
        case exaAPIKey

        var environmentNames: [String] {
            switch self {
            case .claudeAPIKey:
                return ["ANTHROPIC_API_KEY", "BROWSE_CLAUDE_API_KEY", "CLAUDE_API_KEY"]
            case .exaAPIKey:
                return ["EXA_API_KEY", "BROWSE_EXA_API_KEY"]
            }
        }
    }

    func read(_ key: Key) -> String? {
        Self.store.read(key)
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
