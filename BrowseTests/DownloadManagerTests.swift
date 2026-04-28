import Foundation
import Testing
@testable import Browse

@Suite("DownloadManager")
struct DownloadManagerTests {
    @Test("Suggested filenames are sanitized before writing to Downloads")
    func suggestedFilenamesAreSanitized() {
        #expect(DownloadDestinationResolver.sanitizedFilename("") == "Download")
        #expect(DownloadDestinationResolver.sanitizedFilename("  report.pdf  ") == "report.pdf")
        #expect(DownloadDestinationResolver.sanitizedFilename("../private:file.txt") == "..-private-file.txt")
        #expect(DownloadDestinationResolver.sanitizedFilename("folder/name\nnext.txt") == "folder-name-next.txt")
        #expect(DownloadDestinationResolver.sanitizedFilename(".") == "Download")
        #expect(DownloadDestinationResolver.sanitizedFilename("..") == "Download")
    }

    @Test("Destination resolver avoids overwriting existing downloads")
    func destinationResolverAvoidsOverwritingExistingDownloads() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let existingURL = directory.appendingPathComponent("archive.zip")
        let secondExistingURL = directory.appendingPathComponent("archive 2.zip")
        FileManager.default.createFile(atPath: existingURL.path, contents: Data())
        FileManager.default.createFile(atPath: secondExistingURL.path, contents: Data())

        let resolver = DownloadDestinationResolver(downloadsDirectoryURL: directory)
        let destinationURL = resolver.destinationURL(for: "archive.zip")

        #expect(destinationURL.lastPathComponent == "archive 3.zip")
    }

    @MainActor
    @Test("Clearing completed entries keeps active and failed downloads")
    func clearingCompletedEntriesKeepsActiveAndFailedDownloads() {
        let active = DownloadItem(filename: "active.txt", state: .downloading)
        let failed = DownloadItem(filename: "failed.txt", state: .failed)
        let completed = DownloadItem(filename: "done.txt", state: .completed)

        let remaining = DownloadManager.entriesAfterClearingCompleted([active, failed, completed])

        #expect(remaining.map(\.id) == [active.id, failed.id])
    }

    @MainActor
    @Test("Persisted download items include only recent inactive entries")
    func persistedDownloadItemsIncludeOnlyRecentInactiveEntries() throws {
        let active = DownloadItem(filename: "active.txt", state: .downloading)
        let firstCompleted = DownloadItem(
            filename: "first.txt",
            sourceURL: URL(string: "https://example.com/private/path?token=secret"),
            destinationURL: URL(filePath: "/tmp/first.txt"),
            progress: 1,
            state: .completed
        )
        let secondCompleted = DownloadItem(
            filename: "second.txt",
            sourceURL: URL(string: "file:///tmp/source.txt"),
            destinationURL: URL(filePath: "/tmp/second.txt"),
            progress: 1,
            state: .completed
        )

        let persistedItems = DownloadManager.persistedDownloadItems(
            from: [active, firstCompleted, secondCompleted],
            maxEntries: 1
        )

        #expect(persistedItems.map(\.filename) == ["first.txt"])
        #expect(persistedItems.first?.sourceURL?.absoluteString == "https://example.com")
    }

    @MainActor
    @Test("Restored downloads keep completed and failed entries without retry state")
    func restoredDownloadsKeepCompletedAndFailedEntriesWithoutRetryState() throws {
        let completedID = UUID()
        let failedID = UUID()
        let restoredItems = DownloadManager.restoredDownloadItems(from: [
            PersistedDownloadItem(
                id: completedID,
                filename: "done.txt",
                sourceURL: URL(string: "https://example.com"),
                destinationURL: URL(filePath: "/tmp/done.txt"),
                progress: 0.4,
                state: .completed,
                errorSummary: nil
            ),
            PersistedDownloadItem(
                id: failedID,
                filename: "failed.txt",
                sourceURL: URL(string: "https://example.com"),
                destinationURL: nil,
                progress: 0.25,
                state: .failed,
                errorSummary: "Network connection was lost."
            ),
            PersistedDownloadItem(
                id: UUID(),
                filename: "active.txt",
                sourceURL: nil,
                destinationURL: nil,
                progress: 0.5,
                state: .downloading,
                errorSummary: nil
            )
        ])

        #expect(restoredItems.map(\.id) == [completedID, failedID])
        #expect(restoredItems[0].progress == 1)
        #expect(restoredItems[1].progress == 0.25)
        #expect(!restoredItems[1].isRetryAvailable)
    }

    @Test("Download history store saves and loads JSON")
    func downloadHistoryStoreSavesAndLoadsJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = DownloadHistoryStore(
            fileURL: directory.appendingPathComponent("downloads.json")
        )
        let item = PersistedDownloadItem(
            id: UUID(),
            filename: "report.pdf",
            sourceURL: URL(string: "https://example.com"),
            destinationURL: URL(filePath: "/tmp/report.pdf"),
            progress: 1,
            state: .completed,
            errorSummary: nil
        )

        try store.save([item])

        #expect(store.load() == [item])
    }
}
