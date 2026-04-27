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
            let executablePath = CommandLine.arguments.first ?? fileManager.currentDirectoryPath
            let startPaths = [
                fileManager.currentDirectoryPath,
                (executablePath as NSString).deletingLastPathComponent,
                Bundle.main.bundleURL.path,
                (sourceFilePath as NSString).deletingLastPathComponent,
            ]

            for startPath in startPaths {
                if let envURL = findDotEnv(ascendingFromPath: startPath, fileManager: fileManager) {
                    return envURL
                }
            }
            return nil
        }

        private static func findDotEnv(ascendingFromPath startPath: String, fileManager: FileManager) -> URL? {
            var directory = (startPath as NSString).standardizingPath
            var visited = Set<String>()

            for _ in 0..<64 {
                guard !visited.contains(directory) else { return nil }
                visited.insert(directory)

                let envPath = (directory as NSString).appendingPathComponent(".env")
                if fileManager.fileExists(atPath: envPath) {
                    return URL(fileURLWithPath: envPath)
                }

                let parent = (directory as NSString).deletingLastPathComponent
                guard !parent.isEmpty, parent != directory else {
                    return nil
                }
                directory = parent
            }

            return nil
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
