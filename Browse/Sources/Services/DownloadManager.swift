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

    init(
        id: UUID = UUID(),
        filename: String,
        sourceURL: URL? = nil,
        destinationURL: URL? = nil,
        progress: Double = 0,
        state: DownloadState = .waiting,
        errorSummary: String? = nil,
        isRetryAvailable: Bool = false
    ) {
        self.id = id
        self.filename = filename
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.progress = progress
        self.state = state
        self.errorSummary = errorSummary
        self.isRetryAvailable = isRetryAvailable
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
    private var activeDownloadsByObjectID: [ObjectIdentifier: ActiveDownload] = [:]
    private var downloadsByItemID: [DownloadItem.ID: WKDownload] = [:]
    private var progressObservationsByItemID: [DownloadItem.ID: NSKeyValueObservation] = [:]
    private var resumeDataByItemID: [DownloadItem.ID: Data] = [:]
    private var sourceWebViewsByItemID: [DownloadItem.ID: WeakWebViewBox] = [:]

    init(downloadsDirectoryURL: URL? = nil, fileManager: FileManager = .default) {
        let resolvedDownloadsDirectory = downloadsDirectoryURL
            ?? fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.destinationResolver = DownloadDestinationResolver(
            downloadsDirectoryURL: resolvedDownloadsDirectory,
            fileManager: fileManager
        )
        super.init()
    }

    var activeCount: Int {
        downloads.filter(\.isActive).count
    }

    var hasCompletedDownloads: Bool {
        downloads.contains { $0.state == .completed }
    }

    func begin(_ download: WKDownload, sourceURL: URL? = nil, item existingItem: DownloadItem? = nil) {
        let item = existingItem ?? DownloadItem(
            filename: filename(from: sourceURL ?? download.originalRequest?.url),
            sourceURL: sourceURL ?? download.originalRequest?.url,
            state: .waiting
        )

        if existingItem == nil {
            downloads.insert(item, at: 0)
        }

        item.sourceURL = item.sourceURL ?? sourceURL ?? download.originalRequest?.url
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
            return
        }

        item.state = .waiting
        item.progress = 0
        item.errorSummary = nil
        item.destinationURL = nil
        item.isRetryAvailable = false

        if let resumeData = resumeDataByItemID[item.id] {
            resumeDataByItemID[item.id] = nil
            webView.resumeDownload(fromResumeData: resumeData) { [weak self, weak item] download in
                guard let self, let item else { return }
                self.begin(download, sourceURL: item.sourceURL, item: item)
            }
        } else if let sourceURL = item.sourceURL {
            webView.startDownload(using: URLRequest(url: sourceURL)) { [weak self, weak item] download in
                guard let self, let item else { return }
                self.begin(download, sourceURL: sourceURL, item: item)
            }
        } else {
            item.state = .failed
            item.errorSummary = "The original download URL is unavailable."
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
    }

    static func entriesAfterClearingCompleted(_ downloads: [DownloadItem]) -> [DownloadItem] {
        downloads.filter { $0.state != .completed }
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
    }
}
