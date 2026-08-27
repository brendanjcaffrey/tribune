import Foundation
import Testing
@testable import Tribune

// MARK: - mocks

@MainActor
final class MockDownloadSettings: DownloadSettings {
    var downloadMode = true
    var downloadOnCellular = true
}

@MainActor
final class MockFileStore: FileStoring {
    /// files that are already on disk
    var existing: Set<String> = []
    private(set) var written: [(type: FileType, id: Int, data: Data)] = []
    private(set) var deleted: [(type: FileType, id: Int)] = []

    private func key(_ type: FileType, _ id: Int) -> String { "\(type.rawValue):\(id)" }

    func markExisting(type: FileType, id: Int) {
        existing.insert(key(type, id))
    }

    func fileExists(type: FileType, id: Int) -> Bool {
        existing.contains(key(type, id))
    }

    @discardableResult
    func writeFile(type: FileType, id: Int, data: Data) -> Bool {
        written.append((type, id, data))
        existing.insert(key(type, id))
        return true
    }

    func deleteFile(type: FileType, id: Int) {
        deleted.append((type, id))
        existing.remove(key(type, id))
    }
}

@MainActor
final class MockFileFetcher: NewsletterFileFetching {
    private(set) var fetched: [(type: APIFileType, id: Int)] = []

    /// thrown instead of returning data
    var error: Error?

    /// a fetch of this newsletter blocks until `release()` is called, or until
    /// the surrounding task is cancelled
    var holdId: Int?
    private var released = false

    func fetch(type: APIFileType, id: Int) async throws -> Data {
        fetched.append((type, id))

        if id == holdId {
            // Task.sleep throws if we get cancelled, which is how a real
            // download in flight would bail out
            while !released {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        }

        if let error { throw error }
        return Data("\(type)-\(id)".utf8)
    }

    func release() {
        released = true
    }
}

// MARK: - tests

@MainActor
struct DownloadManagerTests {
    let library = MockLibrary()
    let settings = MockDownloadSettings()
    let files = MockFileStore()
    let fetcher = MockFileFetcher()

    private func makeManager() -> DownloadManager {
        DownloadManager(
            library: library,
            settings: settings,
            files: files,
            fetcher: fetcher,
            monitorReachability: false
        )
    }

    private func newsletter(
        id: Int,
        mimeType: String = "text/html",
        epubUpdatedAt: String = "v1",
        sourceUpdatedAt: String = "v1",
        epubVersion: String? = nil,
        sourceVersion: String? = nil,
        epubLastAccessedAt: Date? = nil,
        sourceLastAccessedAt: Date? = nil
    ) -> Newsletter {
        Newsletter(
            id: id,
            title: "newsletter \(id)",
            author: "author",
            sourceId: "https://example.com/\(id)",
            sourceMimeType: mimeType,
            read: false,
            deleted: false,
            progress: "",
            createdAt: .now,
            updatedAt: "v1",
            epubUpdatedAt: epubUpdatedAt,
            sourceUpdatedAt: sourceUpdatedAt,
            epubVersion: epubVersion,
            sourceVersion: sourceVersion,
            epubLastAccessedAt: epubLastAccessedAt,
            sourceLastAccessedAt: sourceLastAccessedAt
        )
    }

    private func runAPass(_ manager: DownloadManager) async {
        await manager.checkForDownloads()
        await manager.waitForCurrentWork()
    }

    private static let daysAgo: (Double) -> Date = { Date(timeIntervalSinceNow: -$0 * 24 * 60 * 60) }

    // MARK: - when downloading is allowed

    @Test func doesNotDownloadWhenDownloadModeIsOff() async {
        settings.downloadMode = false
        library.unreadUndeleted = [newsletter(id: 1)]

        await runAPass(makeManager())

        #expect(fetcher.fetched.isEmpty)
        #expect(files.written.isEmpty)
    }

    @Test func doesNotDownloadOverCellularUnlessAllowed() async {
        settings.downloadOnCellular = false
        library.unreadUndeleted = [newsletter(id: 1)]

        // no wifi, and cellular isn't allowed
        await runAPass(makeManager())

        #expect(fetcher.fetched.isEmpty)
    }

    @Test func downloadsOverCellularWhenAllowed() async {
        settings.downloadOnCellular = true
        library.unreadUndeleted = [newsletter(id: 1)]

        await runAPass(makeManager())

        #expect(fetcher.fetched.map(\.id) == [1])
    }

    @Test func downloadsOnWifiEvenWhenCellularIsNotAllowed() async {
        settings.downloadOnCellular = false
        library.unreadUndeleted = [newsletter(id: 1)]
        let manager = makeManager()

        // joining wifi kicks off a pass by itself
        manager.networkChanged(onWifi: true)

        #expect(await waitUntil { fetcher.fetched.map(\.id) == [1] })
        #expect(manager.onWifi)
    }

    // MARK: - downloading epubs

    @Test func downloadsMissingEpubsOldestFirst() async {
        library.unreadUndeleted = [newsletter(id: 1), newsletter(id: 2)]

        await runAPass(makeManager())

        #expect(fetcher.fetched.map(\.id) == [1, 2])
        #expect(files.written.map(\.id) == [1, 2])
        #expect(files.written.allSatisfy { $0.type == .epub })
        #expect(library.saveCount == 2)
    }

    @Test func recordsTheVersionAndAccessTimeOfADownloadedEpub() async {
        let n = newsletter(id: 1, epubUpdatedAt: "v2")
        library.unreadUndeleted = [n]

        await runAPass(makeManager())

        #expect(n.epubVersion == "v2")
        #expect(n.epubLastAccessedAt != nil)
    }

    @Test func skipsAnEpubThatIsAlreadyDownloadedAtTheCurrentVersion() async {
        library.unreadUndeleted = [newsletter(id: 1, epubUpdatedAt: "v1", epubVersion: "v1")]
        files.markExisting(type: .epub, id: 1)

        await runAPass(makeManager())

        #expect(fetcher.fetched.isEmpty)
        #expect(library.saveCount == 0)
    }

    @Test func redownloadsAnEpubWhoseVersionIsStale() async {
        library.unreadUndeleted = [newsletter(id: 1, epubUpdatedAt: "v2", epubVersion: "v1")]
        files.markExisting(type: .epub, id: 1)

        await runAPass(makeManager())

        #expect(fetcher.fetched.map(\.id) == [1])
        #expect(files.written.map(\.id) == [1])
    }

    /// a pass goes by the recorded version alone. that's fine because anything
    /// that removes a file (the cleanup below) clears the version with it
    @Test func aPassSkipsAnEpubWhoseVersionIsCurrentEvenIfTheFileIsGone() async {
        library.unreadUndeleted = [newsletter(id: 1, epubUpdatedAt: "v1", epubVersion: "v1")]

        await runAPass(makeManager())

        #expect(fetcher.fetched.isEmpty)
    }

    /// opening a newsletter downloads it directly, and that path does check
    @Test func downloadsAnEpubWhoseFileWentMissingWhenItIsOpened() async throws {
        let n = newsletter(id: 1, epubUpdatedAt: "v1", epubVersion: "v1")

        try await makeManager().downloadEpub(newsletter: n)

        #expect(fetcher.fetched.map(\.id) == [1])
        #expect(files.written.map(\.id) == [1])
    }

    @Test func doesNotRedownloadAnEpubThatIsAlreadyThereWhenItIsOpened() async throws {
        let n = newsletter(id: 1, epubUpdatedAt: "v1", epubVersion: "v1")
        files.markExisting(type: .epub, id: 1)

        try await makeManager().downloadEpub(newsletter: n)

        #expect(fetcher.fetched.isEmpty)
        #expect(library.saveCount == 0)
    }

    @Test func stopsThePassWhenADownloadFails() async {
        library.unreadUndeleted = [newsletter(id: 1), newsletter(id: 2)]
        fetcher.error = APIError.badStatus(500)
        let manager = makeManager()

        await runAPass(manager)

        #expect(fetcher.fetched.map(\.id) == [1])
        #expect(files.written.isEmpty)
        #expect(manager.currentEpubDownloadId == nil)

        // and the next pass picks it up again
        fetcher.error = nil
        await runAPass(manager)
        #expect(files.written.map(\.id) == [1, 2])
    }

    @Test func publishesWhichEpubIsDownloading() async {
        library.unreadUndeleted = [newsletter(id: 7)]
        fetcher.holdId = 7
        let manager = makeManager()

        await manager.checkForDownloads()
        #expect(await waitUntil { manager.currentEpubDownloadId == 7 })

        fetcher.release()
        await manager.waitForCurrentWork()
        #expect(manager.currentEpubDownloadId == nil)
    }

    // MARK: - downloading sources

    @Test func downloadsTheSourceUsingItsOwnFileType() async throws {
        let n = newsletter(id: 1, mimeType: "application/pdf", sourceUpdatedAt: "v2")
        let manager = makeManager()

        try await manager.downloadSource(newsletter: n)

        #expect(fetcher.fetched.map(\.type) == [.source])
        #expect(files.written.map(\.type) == [.pdf])
        #expect(n.sourceVersion == "v2")
        #expect(n.sourceLastAccessedAt != nil)
        #expect(manager.currentSourceDownloadId == nil)
        #expect(library.saveCount == 1)
    }

    @Test func skipsASourceThatIsAlreadyDownloadedAtTheCurrentVersion() async throws {
        let n = newsletter(id: 1, sourceUpdatedAt: "v1", sourceVersion: "v1")
        files.markExisting(type: .html, id: 1)

        try await makeManager().downloadSource(newsletter: n)

        #expect(fetcher.fetched.isEmpty)
        #expect(library.saveCount == 0)
    }

    // MARK: - deleting stale files

    @Test func deletesFilesThatHaventBeenOpenedInDays() async {
        let n = newsletter(
            id: 1,
            epubVersion: "v1",
            sourceVersion: "v1",
            epubLastAccessedAt: Self.daysAgo(4),
            sourceLastAccessedAt: Self.daysAgo(4)
        )
        library.withFilesToDelete = [n]

        await runAPass(makeManager())

        #expect(files.deleted.map(\.type) == [.epub, .html])
        #expect(n.epubLastAccessedAt == nil)
        #expect(n.epubVersion == nil)
        #expect(n.sourceLastAccessedAt == nil)
        #expect(n.sourceVersion == nil)
    }

    @Test func keepsFilesThatWereOpenedRecently() async {
        let n = newsletter(
            id: 1,
            epubVersion: "v1",
            epubLastAccessedAt: Self.daysAgo(1),
            sourceLastAccessedAt: Self.daysAgo(2)
        )
        library.withFilesToDelete = [n]

        await runAPass(makeManager())

        #expect(files.deleted.isEmpty)
        #expect(n.epubVersion == "v1")
    }

    @Test func onlyDeletesTheFileThatWentStale() async {
        let n = newsletter(
            id: 1,
            epubVersion: "v1",
            sourceVersion: "v1",
            epubLastAccessedAt: Self.daysAgo(10),
            sourceLastAccessedAt: Self.daysAgo(1)
        )
        library.withFilesToDelete = [n]

        await runAPass(makeManager())

        #expect(files.deleted.map(\.type) == [.epub])
        #expect(n.epubVersion == nil)
        #expect(n.sourceVersion == "v1")
    }

    @Test func leavesFilesAloneWhenTheyWereNeverOpened() async {
        library.withFilesToDelete = [newsletter(id: 1)]

        await runAPass(makeManager())

        #expect(files.deleted.isEmpty)
    }

    @Test func stillCleansUpWhenDownloadingIsTurnedOff() async {
        settings.downloadMode = false
        library.withFilesToDelete = [
            newsletter(id: 1, epubVersion: "v1", epubLastAccessedAt: Self.daysAgo(4))
        ]

        await runAPass(makeManager())

        #expect(files.deleted.map(\.id) == [1])
    }

    // MARK: - one pass at a time, and cancelling

    @Test func doesNotStartASecondPassWhileOneIsRunning() async {
        library.unreadUndeleted = [newsletter(id: 1), newsletter(id: 2)]
        fetcher.holdId = 1
        let manager = makeManager()

        await manager.checkForDownloads()
        #expect(await waitUntil { !fetcher.fetched.isEmpty })
        await manager.checkForDownloads()

        fetcher.release()
        await manager.waitForCurrentWork()

        #expect(fetcher.fetched.map(\.id) == [1, 2])
    }

    @Test func cancelsTheCurrentPassWhenDownloadModeIsTurnedOff() async {
        library.unreadUndeleted = [newsletter(id: 1), newsletter(id: 2)]
        fetcher.holdId = 1
        let manager = makeManager()

        await manager.checkForDownloads()
        #expect(await waitUntil { !fetcher.fetched.isEmpty })
        let pass = manager.currentTask

        settings.downloadMode = false
        manager.checkIfCancelNeeded()
        await pass?.value

        // the held download bailed out, and 2 was never started
        #expect(fetcher.fetched.map(\.id) == [1])
        #expect(files.written.isEmpty)
    }

    @Test func cancelsTheCurrentPassWhenWifiGoesAwayAndCellularIsNotAllowed() async {
        settings.downloadOnCellular = false
        library.unreadUndeleted = [newsletter(id: 1), newsletter(id: 2)]
        fetcher.holdId = 1
        let manager = makeManager()

        manager.networkChanged(onWifi: true)
        #expect(await waitUntil { !fetcher.fetched.isEmpty })
        let pass = manager.currentTask

        manager.networkChanged(onWifi: false)
        await pass?.value

        #expect(manager.onWifi == false)
        #expect(fetcher.fetched.map(\.id) == [1])
        #expect(files.written.isEmpty)
    }

    @Test func keepsGoingWhenTheNetworkChangesButCellularIsAllowed() async {
        settings.downloadOnCellular = true
        library.unreadUndeleted = [newsletter(id: 1), newsletter(id: 2)]
        fetcher.holdId = 1
        let manager = makeManager()

        manager.networkChanged(onWifi: true)
        #expect(await waitUntil { !fetcher.fetched.isEmpty })

        manager.networkChanged(onWifi: false)
        fetcher.release()
        await manager.waitForCurrentWork()

        #expect(fetcher.fetched.map(\.id) == [1, 2])
        #expect(files.written.map(\.id) == [1, 2])
    }

    @Test func canRunAnotherPassAfterOneWasCancelled() async {
        library.unreadUndeleted = [newsletter(id: 1)]
        fetcher.holdId = 1
        let manager = makeManager()

        await manager.checkForDownloads()
        #expect(await waitUntil { !fetcher.fetched.isEmpty })
        let pass = manager.currentTask
        manager.reset()
        await pass?.value

        fetcher.holdId = nil
        await runAPass(manager)

        #expect(files.written.map(\.id) == [1])
    }
}
