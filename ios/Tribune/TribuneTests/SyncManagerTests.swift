import Foundation
import Testing
@testable import Tribune

// MARK: - mocks

@MainActor
final class MockNewsletterListFetcher: NewsletterListFetching {
    /// what a full fetch returns
    var all: [NewslettersResponse.Item] = []

    /// handed out one per `fetchAfter`, in order. once they run out, and by
    /// default, an empty page comes back so paging stops
    var pages: [[NewslettersResponse.Item]] = []

    private(set) var fetchAllCount = 0
    /// the ids of the newsletters we were asked to fetch after, in order
    private(set) var fetchedAfter: [Int] = []

    /// thrown instead of returning a page
    var error: Error?

    /// when set, pages are answered the way the server does instead of being
    /// handed out from `pages`: every row above the cursor, oldest first, cut
    /// off at `pageSize`
    var serverRows: [NewslettersResponse.Item]?
    var pageSize = 100

    /// a sync whose cursor never advances would ask forever, so give up and
    /// throw rather than hanging the test
    var maxFetches = 20
    struct RunawaySync: Error {}

    /// fetches block until `release()` is called, or the sync is cancelled
    var hold = false
    private var released = false

    func fetchAll() async throws -> NewslettersResponse {
        fetchAllCount += 1
        try await waitIfHeld()
        if let error { throw error }
        return NewslettersResponse(result: all)
    }

    func fetchAfter(newsletter: Newsletter) async throws -> NewslettersResponse {
        fetchedAfter.append(newsletter.id)
        if fetchedAfter.count > maxFetches { throw RunawaySync() }
        try await waitIfHeld()
        if let error { throw error }
        if let serverRows {
            let above = serverRows
                .filter {
                    $0.updated_at == newsletter.updatedAt
                        ? $0.id > newsletter.id
                        : $0.updated_at > newsletter.updatedAt
                }
                .sorted { $0.updated_at == $1.updated_at ? $0.id < $1.id : $0.updated_at < $1.updated_at }
            return NewslettersResponse(result: Array(above.prefix(pageSize)))
        }
        return NewslettersResponse(result: pages.isEmpty ? [] : pages.removeFirst())
    }

    private func waitIfHeld() async throws {
        guard hold else { return }
        // Task.sleep throws if we get cancelled, which is how a real request in
        // flight would bail out
        while !released {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func release() {
        released = true
    }
}

@MainActor
final class MockDownloadManager: DownloadManaging {
    private(set) var checkCount = 0

    func checkForDownloads() async {
        checkCount += 1
    }
}

// MARK: - tests

@MainActor
struct SyncManagerTests {
    let library = MockLibrary()
    let fetcher = MockNewsletterListFetcher()
    let downloads = MockDownloadManager()

    private func makeManager() -> SyncManager {
        SyncManager(library: library, downloadManager: downloads, fetcher: fetcher)
    }

    private func item(
        id: Int,
        title: String = "a newsletter",
        read: Bool = false,
        deleted: Bool = false,
        updatedAt: String = "2025-01-01 06:00:00+00",
        epubUpdatedAt: String = "v1"
    ) -> NewslettersResponse.Item {
        NewslettersResponse.Item(
            id: id,
            title: title,
            author: "author",
            source_id: "https://example.com/\(id)",
            source_mime_type: "text/html",
            read: read,
            deleted: deleted,
            progress: "",
            created_at: .now,
            updated_at: updatedAt,
            epub_updated_at: epubUpdatedAt,
            source_updated_at: "v1"
        )
    }

    private func newsletter(
        id: Int,
        updatedAt: String = "2025-01-01 06:00:00+00",
        epubVersion: String? = nil,
        epubLastAccessedAt: Date? = nil
    ) -> Newsletter {
        Newsletter(
            id: id,
            title: "newsletter \(id)",
            author: "author",
            sourceId: "https://example.com/\(id)",
            sourceMimeType: "text/html",
            read: false,
            deleted: false,
            progress: "",
            createdAt: .now,
            updatedAt: updatedAt,
            epubUpdatedAt: "v1",
            sourceUpdatedAt: "v1",
            epubVersion: epubVersion,
            epubLastAccessedAt: epubLastAccessedAt
        )
    }

    /// let any fire and forget work (the download kick off) get a turn
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    // MARK: - the initial fetch

    @Test func fetchesTheWholeLibraryWhenThereIsNothingStored() async {
        fetcher.all = [item(id: 1), item(id: 2)]

        let status = await makeManager().syncLibrary()

        #expect(status == .success)
        #expect(fetcher.fetchAllCount == 1)
        #expect(fetcher.fetchedAfter.isEmpty)
        #expect(library.put.map(\.id) == [1, 2])
    }

    @Test func storesEverythingTheServerSentOnTheFirstSync() async {
        fetcher.all = [item(id: 1, title: "hello", read: true)]

        await makeManager().syncLibrary()

        let stored = library.lastPut(id: 1)
        #expect(stored?.title == "hello")
        #expect(stored?.read == true)
        // nothing is downloaded yet, so there's no local state to carry over
        #expect(stored?.epubVersion == nil)
        #expect(stored?.epubLastAccessedAt == nil)
    }

    // MARK: - incremental fetches

    @Test func fetchesOnlyWhatIsNewerWhenTheLibraryIsPopulated() async {
        library.stored = [
            newsletter(id: 1, updatedAt: "2025-01-01 06:00:00+00"),
            newsletter(id: 2, updatedAt: "2025-02-01 06:00:00+00"),
        ]

        let status = await makeManager().syncLibrary()

        #expect(status == .success)
        #expect(fetcher.fetchAllCount == 0)
        // asked after the newest one it already had
        #expect(fetcher.fetchedAfter == [2])
    }

    @Test func keepsPagingUntilAPageComesBackEmpty() async {
        library.stored = [newsletter(id: 1, updatedAt: "2025-01-01 06:00:00+00")]
        fetcher.pages = [
            [item(id: 2, updatedAt: "2025-01-02 06:00:00+00")],
            [item(id: 3, updatedAt: "2025-01-03 06:00:00+00")],
            [],
        ]

        await makeManager().syncLibrary()

        // each page moves the cursor on to the newest newsletter it just stored
        #expect(fetcher.fetchedAfter == [1, 2, 3])
        #expect(library.put.map(\.id) == [2, 3])
    }

    @Test func finishesWhenTheTwoNewestNewslettersShareATimestamp() async {
        // updated_at defaults to the transaction's start time, so newsletters
        // written together carry identical timestamps. the cursor has to break
        // that tie the way the server does, on the highest id -- picking the
        // lowest asks after 5, gets handed 9, and asks after 5 again forever
        let tie = "2025-02-01 06:00:00+00"
        library.stored = [
            newsletter(id: 5, updatedAt: tie),
            newsletter(id: 9, updatedAt: tie),
        ]
        fetcher.serverRows = [item(id: 5, updatedAt: tie), item(id: 9, updatedAt: tie)]

        let status = await makeManager().syncLibrary()

        #expect(status == .success)
        #expect(fetcher.fetchedAfter == [9])
    }

    @Test func walksATiedTimestampToTheEndWithoutRepeatingItself() async {
        // the whole page shares one timestamp, so every step of the walk is a
        // tie and the cursor can only move on the id
        let tie = "2025-02-01 06:00:00+00"
        library.stored = [newsletter(id: 1, updatedAt: tie)]
        fetcher.serverRows = (1...7).map { item(id: $0, updatedAt: tie) }
        fetcher.pageSize = 2

        let status = await makeManager().syncLibrary()

        #expect(status == .success)
        #expect(fetcher.fetchedAfter == [1, 3, 5, 7])
        #expect(library.put.map(\.id) == [2, 3, 4, 5, 6, 7])
    }

    @Test func doesNothingWhenTheLibrarySaysItHasNewslettersButCantFindOne() async {
        // hasAnyNewsletters and getNewestNewsletter disagreeing shouldn't crash
        library.stored = []
        let manager = SyncManager(
            library: EmptyButNonEmptyLibrary(),
            downloadManager: downloads,
            fetcher: fetcher
        )

        let status = await manager.syncLibrary()

        #expect(status == .success)
        #expect(fetcher.fetchedAfter.isEmpty)
        #expect(fetcher.fetchAllCount == 0)
    }

    // MARK: - keeping local state

    @Test func keepsWhatIsDownloadedLocallyWhenANewsletterIsUpdated() async {
        let accessed = Date(timeIntervalSince1970: 1_700_000_000)
        library.stored = [
            newsletter(id: 1, epubVersion: "v1", epubLastAccessedAt: accessed)
        ]
        fetcher.pages = [[item(id: 1, title: "new title", epubUpdatedAt: "v2")], []]

        await makeManager().syncLibrary()

        let updated = library.lastPut(id: 1)
        #expect(updated?.title == "new title")
        #expect(updated?.epubUpdatedAt == "v2")
        // the download itself is still the old one, and is what marks it stale
        #expect(updated?.epubVersion == "v1")
        #expect(updated?.epubLastAccessedAt == accessed)
    }

    @Test func doesNotInventLocalStateForANewsletterItHasNotSeen() async {
        library.stored = [newsletter(id: 1, epubVersion: "v1")]
        fetcher.pages = [[item(id: 2)], []]

        await makeManager().syncLibrary()

        #expect(library.lastPut(id: 2)?.epubVersion == nil)
    }

    // MARK: - failures

    @Test func reportsAFailedFetch() async {
        fetcher.error = APIError.badStatus(500)

        let status = await makeManager().syncLibrary()

        #expect(status == .error(APIError.badStatus(500).localizedDescription))
        #expect(library.put.isEmpty)
    }

    @Test func reportsAFailedLibraryRead() async {
        library.error = APIError.notAuthorized

        let status = await makeManager().syncLibrary()

        #expect(status == .error(APIError.notAuthorized.localizedDescription))
    }

    @Test func canSyncAgainAfterAFailure() async {
        fetcher.error = APIError.badStatus(500)
        let manager = makeManager()
        #expect(await manager.syncLibrary() != .success)

        fetcher.error = nil
        fetcher.all = [item(id: 1)]
        #expect(await manager.syncLibrary() == .success)
        #expect(library.put.map(\.id) == [1])
    }

    // MARK: - downloads

    @Test func kicksOffDownloadsAfterASuccessfulSync() async {
        fetcher.all = [item(id: 1)]

        await makeManager().syncLibrary()

        #expect(await waitUntil { downloads.checkCount == 1 })
    }

    @Test func doesNotKickOffDownloadsWhenAskedToSkipThem() async {
        fetcher.all = [item(id: 1)]

        await makeManager().syncLibrary(skipDownload: true)
        await settle()

        #expect(downloads.checkCount == 0)
    }

    @Test func doesNotKickOffDownloadsWhenTheSyncFailed() async {
        fetcher.error = APIError.badStatus(500)

        await makeManager().syncLibrary()
        await settle()

        #expect(downloads.checkCount == 0)
    }

    // MARK: - one sync at a time, and cancelling

    @Test func blocksASecondSyncWhileOneIsRunning() async {
        fetcher.hold = true
        fetcher.all = [item(id: 1)]
        let manager = makeManager()

        let first = Task { await manager.syncLibrary() }
        #expect(await waitUntil { fetcher.fetchAllCount == 1 })

        #expect(await manager.syncLibrary() == .blocked)
        #expect(fetcher.fetchAllCount == 1)

        fetcher.release()
        #expect(await first.value == .success)
    }

    @Test func reportsBlockedWhenTheSyncIsCancelled() async {
        fetcher.hold = true
        fetcher.all = [item(id: 1)]
        let manager = makeManager()

        let sync = Task { await manager.syncLibrary() }
        #expect(await waitUntil { fetcher.fetchAllCount == 1 })

        manager.reset()

        #expect(await sync.value == .blocked)
        #expect(library.put.isEmpty)
        await settle()
        #expect(downloads.checkCount == 0)
    }

    @Test func canSyncAgainAfterOneWasCancelled() async {
        fetcher.hold = true
        fetcher.all = [item(id: 1)]
        let manager = makeManager()

        let sync = Task { await manager.syncLibrary() }
        #expect(await waitUntil { fetcher.fetchAllCount == 1 })
        manager.reset()
        _ = await sync.value

        fetcher.hold = false
        #expect(await manager.syncLibrary() == .success)
        #expect(library.put.map(\.id) == [1])
    }
}

/// claims to have newsletters but can't produce one, so the incremental fetch
/// has nothing to page from
@MainActor
private final class EmptyButNonEmptyLibrary: LibraryProtocol {
    func hasAnyNewsletters() async throws -> Bool { true }
    func getNewestNewsletter() async throws -> Newsletter? { nil }
    func getAllNewsletters() async throws -> [Newsletter] { [] }
    func getUnreadUndeletedNewsletters() async throws -> [Newsletter] { [] }
    func getNewslettersWithFilesToDelete() async throws -> [Newsletter] { [] }
    func putNewsletter(_ n: Newsletter) async throws {}
    func findById(_ id: Int) async throws -> Newsletter? { nil }
    func save() throws {}
}
