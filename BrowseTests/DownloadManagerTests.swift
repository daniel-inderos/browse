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
}
