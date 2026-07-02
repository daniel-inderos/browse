import AppKit
import Foundation
import Observation
import WebKit

enum DownloadState: String, Codable {
    case waiting
    case downloading
    case completed
    case failed
}

@Observable
final class DownloadItem: Identifiable, @unchecked Sendable {
    let id: UUID
    var filename: String
    var sourceURL: URL?
    var destinationURL: URL?
    var progress: Double
    var state: DownloadState
    var errorSummary: String?
    var isRetryAvailable: Bool
    var workspaceID: UUID?

    init(
        id: UUID = UUID(),
        filename: String,
        sourceURL: URL? = nil,
        destinationURL: URL? = nil,
        progress: Double = 0,
        state: DownloadState = .waiting,
        errorSummary: String? = nil,
        isRetryAvailable: Bool = false,
        workspaceID: UUID? = nil
    ) {
        self.id = id
        self.filename = filename
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.progress = progress
        self.state = state
        self.errorSummary = errorSummary
        self.isRetryAvailable = isRetryAvailable
        self.workspaceID = workspaceID
    }

    var isActive: Bool {
        state == .waiting || state == .downloading
    }
}

struct DownloadDestinationResolver {
    let downloadsDirectoryURL: URL
    let fileManager: FileManager

    init(downloadsDirectoryURL: URL, fileManager: FileManager = .default) {
        self.downloadsDirectoryURL = downloadsDirectoryURL
        self.fileManager = fileManager
    }

    func destinationURL(for suggestedFilename: String) -> URL {
        try? fileManager.createDirectory(
            at: downloadsDirectoryURL,
            withIntermediateDirectories: true
        )

        let filename = Self.sanitizedFilename(suggestedFilename)
        let baseURL = downloadsDirectoryURL.appendingPathComponent(filename, isDirectory: false)
        guard fileManager.fileExists(atPath: baseURL.path) else { return baseURL }

        let name = (filename as NSString).deletingPathExtension
        let pathExtension = (filename as NSString).pathExtension

        var counter = 2
        while true {
            let candidateName: String
            if pathExtension.isEmpty {
                candidateName = "\(name) \(counter)"
            } else {
                candidateName = "\(name) \(counter).\(pathExtension)"
            }

            let candidateURL = downloadsDirectoryURL.appendingPathComponent(candidateName, isDirectory: false)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            counter += 1
        }
    }

    static func sanitizedFilename(_ suggestedFilename: String) -> String {
        let trimmed = suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "Download" : trimmed
        let invalidCharacters = CharacterSet(charactersIn: "/:\\\0")
            .union(.newlines)
            .union(.controlCharacters)
        let components = fallback.components(separatedBy: invalidCharacters)
        let joined = components
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let sanitized = joined.isEmpty ? "Download" : joined
        return sanitized == "." || sanitized == ".." ? "Download" : sanitized
    }
}

struct PersistedDownloadItem: Codable, Equatable {
    let id: UUID
    let workspaceID: UUID?
    let filename: String
    let sourceURL: URL?
    let destinationURL: URL?
    let progress: Double
    let state: DownloadState
    let errorSummary: String?
}

struct DownloadHistoryStore {
    let fileURL: URL
    let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    init(fileManager: FileManager = .default) {
        let supportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        let appDirectory = supportDirectory.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "Browse",
            isDirectory: true
        )
        self.init(
            fileURL: appDirectory.appendingPathComponent("downloads.json", isDirectory: false),
            fileManager: fileManager
        )
    }

    func load() -> [PersistedDownloadItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([PersistedDownloadItem].self, from: data)) ?? []
    }

    func save(_ items: [PersistedDownloadItem]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try JSONEncoder().encode(items)
        try data.write(to: fileURL, options: [.atomic])
    }
}

@MainActor
@Observable
final class DownloadManager: NSObject {
    static let shared = DownloadManager()

    private final class WeakWebViewBox {
        weak var webView: WKWebView?

        init(_ webView: WKWebView?) {
            self.webView = webView
        }
    }

    private struct ActiveDownload {
        let itemID: DownloadItem.ID
        let sourceURL: URL?
    }

    private(set) var downloads: [DownloadItem] = []

    private let destinationResolver: DownloadDestinationResolver
    private let historyStore: DownloadHistoryStore
    private let maxPersistedEntries: Int
    private var activeDownloadsByObjectID: [ObjectIdentifier: ActiveDownload] = [:]
    private var downloadsByItemID: [DownloadItem.ID: WKDownload] = [:]
    private var progressObservationsByItemID: [DownloadItem.ID: NSKeyValueObservation] = [:]
    private var resumeDataByItemID: [DownloadItem.ID: Data] = [:]
    private var sourceWebViewsByItemID: [DownloadItem.ID: WeakWebViewBox] = [:]

    init(
        downloadsDirectoryURL: URL? = nil,
        fileManager: FileManager = .default,
        historyStore: DownloadHistoryStore? = nil,
        loadsSavedDownloads: Bool = true,
        maxPersistedEntries: Int = 50
    ) {
        let resolvedDownloadsDirectory = downloadsDirectoryURL
            ?? fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.destinationResolver = DownloadDestinationResolver(
            downloadsDirectoryURL: resolvedDownloadsDirectory,
            fileManager: fileManager
        )
        self.historyStore = historyStore ?? DownloadHistoryStore(fileManager: fileManager)
        self.maxPersistedEntries = maxPersistedEntries
        super.init()

        if loadsSavedDownloads {
            self.downloads = Self.restoredDownloadItems(from: self.historyStore.load())
        }
    }

    var activeCount: Int {
        downloads.filter(\.isActive).count
    }

    var hasCompletedDownloads: Bool {
        downloads.contains { $0.state == .completed }
    }

    func begin(
        _ download: WKDownload,
        sourceURL: URL? = nil,
        workspaceID: UUID? = nil,
        item existingItem: DownloadItem? = nil
    ) {
        let item = existingItem ?? DownloadItem(
            filename: filename(from: sourceURL ?? download.originalRequest?.url),
            sourceURL: sourceURL ?? download.originalRequest?.url,
            state: .waiting,
            workspaceID: workspaceID
        )

        if existingItem == nil {
            downloads.insert(item, at: 0)
        }

        item.sourceURL = item.sourceURL ?? sourceURL ?? download.originalRequest?.url
        item.workspaceID = item.workspaceID ?? workspaceID
        item.state = .waiting
        item.progress = 0
        item.errorSummary = nil
        item.isRetryAvailable = false

        register(download, for: item, sourceURL: item.sourceURL)
    }

    func retry(_ item: DownloadItem) {
        guard item.state == .failed else { return }
        guard let webView = sourceWebViewsByItemID[item.id]?.webView else {
            item.errorSummary = "The original browser context is no longer available."
            item.isRetryAvailable = false
            persistRecentDownloads()
            return
        }

        item.state = .waiting
        item.progress = 0
        item.errorSummary = nil
        item.destinationURL = nil
        item.isRetryAvailable = false
        persistRecentDownloads()

        if let resumeData = resumeDataByItemID[item.id] {
            resumeDataByItemID[item.id] = nil
            webView.resumeDownload(fromResumeData: resumeData) { [weak self, weak item] download in
                guard let self, let item else { return }
                self.begin(download, sourceURL: item.sourceURL, workspaceID: item.workspaceID, item: item)
            }
        } else if let sourceURL = item.sourceURL {
            webView.startDownload(using: URLRequest(url: sourceURL)) { [weak self, weak item] download in
                guard let self, let item else { return }
                self.begin(download, sourceURL: sourceURL, workspaceID: item.workspaceID, item: item)
            }
        } else {
            item.state = .failed
            item.errorSummary = "The original download URL is unavailable."
            persistRecentDownloads()
        }
    }

    func open(_ item: DownloadItem) {
        guard item.state == .completed, let destinationURL = item.destinationURL else { return }
        NSWorkspace.shared.open(destinationURL)
    }

    func revealInFinder(_ item: DownloadItem) {
        guard item.state == .completed, let destinationURL = item.destinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }

    func clearCompleted() {
        let completedIDs = downloads
            .filter { $0.state == .completed }
            .map(\.id)
        downloads = Self.entriesAfterClearingCompleted(downloads)

        for id in completedIDs {
            downloadsByItemID[id] = nil
            progressObservationsByItemID[id] = nil
            resumeDataByItemID[id] = nil
            sourceWebViewsByItemID[id] = nil
        }
        persistRecentDownloads()
    }

    static func entriesAfterClearingCompleted(_ downloads: [DownloadItem]) -> [DownloadItem] {
        downloads.filter { $0.state != .completed }
    }

    static func persistedDownloadItems(
        from downloads: [DownloadItem],
        maxEntries: Int
    ) -> [PersistedDownloadItem] {
        Array(
            downloads
                .filter { !$0.isActive }
                .prefix(maxEntries)
                .map { item in
                    PersistedDownloadItem(
                        id: item.id,
                        workspaceID: item.workspaceID,
                        filename: item.filename,
                        sourceURL: persistedSourceURL(from: item.sourceURL),
                        destinationURL: item.destinationURL,
                        progress: item.progress,
                        state: item.state,
                        errorSummary: item.errorSummary
                    )
                }
        )
    }

    static func restoredDownloadItems(from persistedItems: [PersistedDownloadItem]) -> [DownloadItem] {
        persistedItems
            .filter { $0.state == .completed || $0.state == .failed }
            .map { persistedItem in
                DownloadItem(
                    id: persistedItem.id,
                    filename: persistedItem.filename,
                    sourceURL: persistedItem.sourceURL,
                    destinationURL: persistedItem.destinationURL,
                    progress: persistedItem.state == .completed ? 1 : persistedItem.progress,
                    state: persistedItem.state,
                    errorSummary: persistedItem.errorSummary,
                    isRetryAvailable: false,
                    workspaceID: persistedItem.workspaceID
                )
            }
    }

    private static func persistedSourceURL(from sourceURL: URL?) -> URL? {
        guard let sourceURL,
              let scheme = sourceURL.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = sourceURL.host else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = sourceURL.port
        return components.url
    }

    private func register(_ download: WKDownload, for item: DownloadItem, sourceURL: URL?) {
        let objectID = ObjectIdentifier(download)
        download.delegate = self
        activeDownloadsByObjectID[objectID] = ActiveDownload(itemID: item.id, sourceURL: sourceURL)
        downloadsByItemID[item.id] = download
        sourceWebViewsByItemID[item.id] = WeakWebViewBox(download.webView)
        progressObservationsByItemID[item.id] = download.progress.observe(
            \.fractionCompleted,
             options: [.initial, .new]
        ) { [weak self, weak item] progress, _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item else { return }
                self.updateProgress(progress.fractionCompleted, for: item)
            }
        }
    }

    private func updateProgress(_ progress: Double, for item: DownloadItem) {
        guard item.state == .waiting || item.state == .downloading else { return }
        item.progress = max(0, min(progress, 1))
        item.state = item.progress > 0 ? .downloading : .waiting
    }

    private func item(for download: WKDownload) -> DownloadItem? {
        guard let activeDownload = activeDownloadsByObjectID[ObjectIdentifier(download)] else { return nil }
        return downloads.first { $0.id == activeDownload.itemID }
    }

    private func cleanupActiveDownload(_ download: WKDownload) {
        guard let activeDownload = activeDownloadsByObjectID.removeValue(
            forKey: ObjectIdentifier(download)
        ) else { return }
        downloadsByItemID[activeDownload.itemID] = nil
        progressObservationsByItemID[activeDownload.itemID] = nil
    }

    private func persistRecentDownloads() {
        trimInactiveDownloadsIfNeeded()
        let persistedItems = Self.persistedDownloadItems(
            from: downloads,
            maxEntries: maxPersistedEntries
        )
        try? historyStore.save(persistedItems)
    }

    private func trimInactiveDownloadsIfNeeded() {
        let inactiveIDsToKeep = Set(
            downloads
                .filter { !$0.isActive }
                .prefix(maxPersistedEntries)
                .map(\.id)
        )
        downloads.removeAll { item in
            !item.isActive && !inactiveIDsToKeep.contains(item.id)
        }
    }

    private func filename(from url: URL?) -> String {
        guard let url else { return "Download" }
        let lastPathComponent = url.lastPathComponent
        return DownloadDestinationResolver.sanitizedFilename(
            lastPathComponent.isEmpty ? (url.host ?? "Download") : lastPathComponent
        )
    }

    private func errorSummary(for error: Error) -> String {
        if let urlError = error as? URLError {
            return urlError.localizedDescription
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return nsError.localizedDescription
        }
        return error.localizedDescription
    }
}

extension DownloadManager: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor (URL?) -> Void
    ) {
        let item: DownloadItem
        if let existingItem = self.item(for: download) {
            item = existingItem
        } else {
            item = DownloadItem(
                filename: DownloadDestinationResolver.sanitizedFilename(suggestedFilename),
                sourceURL: response.url ?? download.originalRequest?.url
            )
            downloads.insert(item, at: 0)
            register(download, for: item, sourceURL: item.sourceURL)
        }

        let destinationURL = destinationResolver.destinationURL(for: suggestedFilename)
        item.filename = destinationURL.lastPathComponent
        item.destinationURL = destinationURL
        item.sourceURL = item.sourceURL ?? response.url ?? download.originalRequest?.url
        item.state = .downloading
        completionHandler(destinationURL)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let item = item(for: download) else { return }
        item.progress = 1
        item.state = .completed
        item.errorSummary = nil
        item.isRetryAvailable = false
        resumeDataByItemID[item.id] = nil
        cleanupActiveDownload(download)
        persistRecentDownloads()
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let item = item(for: download) else { return }
        item.state = .failed
        item.errorSummary = errorSummary(for: error)
        item.isRetryAvailable = resumeData != nil || item.sourceURL != nil
        if let resumeData {
            resumeDataByItemID[item.id] = resumeData
        }
        cleanupActiveDownload(download)
        persistRecentDownloads()
    }
}
