import Foundation
import Combine

enum SyncStatus: Equatable {
    case success
    case error(String)
    case blocked
}

private let newslettersPageSize = 100

@MainActor
final class SyncManager: ObservableObject {
    private let library: LibraryProtocol
    private let fetcher: NewsletterListFetching
    private weak var downloadManager: DownloadManaging?

    // not private so tests can await a sync they cancelled
    private(set) var currentSyncTask: Task<SyncStatus, Never>?
    @Published private var isSyncing = false

    init(
        library: LibraryProtocol,
        downloadManager: DownloadManaging?,
        fetcher: NewsletterListFetching = APINewsletterListFetcher()
    ) {
        self.library = library
        self.downloadManager = downloadManager
        self.fetcher = fetcher
    }

    func reset() {
        currentSyncTask?.cancel()
        currentSyncTask = nil
    }

    func syncLibrary(skipDownload: Bool = false) async -> SyncStatus {
        guard !isSyncing else { return .blocked }

        if currentSyncTask != nil { fatalError() }
        isSyncing = true

        currentSyncTask = Task { [weak self] in
            guard let self else { return SyncStatus.blocked }
            defer { self.finishSync() }

            do {
                if try await library.hasAnyNewsletters() {
                    try await fetchUpdates()
                } else {
                    try await fetchInitial()
                }

                if !skipDownload {
                    Task { await self.downloadManager?.checkForDownloads() }
                }
                return SyncStatus.success
            } catch is CancellationError {
                return SyncStatus.blocked
            } catch {
                return SyncStatus.error(error.localizedDescription)
            }
        }

        return await currentSyncTask?.value ?? .blocked
    }

    private func fetchInitial() async throws {
        let response = try await fetcher.fetchAll()
        try await storeInitial(response)

        // The initial endpoint starts with the newest page. Walk backwards
        // from each full page so a fresh install receives the full library.
        guard response.result.count == newslettersPageSize,
              let oldest = response.result.last else { return }
        try await fetchInitial(beforeUpdatedAt: oldest.updated_at, id: oldest.id)
    }

    private func fetchInitial(beforeUpdatedAt updatedAt: String, id: Int) async throws {
        let response = try await fetcher.fetchBefore(updatedAt: updatedAt, id: id)
        try await storeInitial(response)

        guard response.result.count == newslettersPageSize,
              let oldest = response.result.last else { return }
        try await fetchInitial(beforeUpdatedAt: oldest.updated_at, id: oldest.id)
    }

    private func storeInitial(_ response: NewslettersResponse) async throws {
        for n in transformResponse(api: response, originalMap: .none) {
            try await library.putNewsletter(n)
        }
    }

    private func fetchUpdates(fetchedAny: Bool = false) async throws {
        let newsletter = try await library.getNewestNewsletter()
        guard let newsletter = newsletter else { return }

        let response = try await fetcher.fetchAfter(newsletter: newsletter)
        let all = try await library.getAllNewsletters()
        let originalMap = buildOriginalNewslettersMap(all: all, api: response)

        for n in transformResponse(api: response, originalMap: originalMap) {
            try await library.putNewsletter(n)
        }

        if !response.result.isEmpty {
            try await fetchUpdates(fetchedAny: true)
        }
    }

    private func buildOriginalNewslettersMap(all: [Newsletter], api: NewslettersResponse) -> [Int: Newsletter] {
        let newIds = Set(api.result.map { $0.id })
        var map: [Int: Newsletter] = [:]
        for n in all where newIds.contains(n.id) {
            map[n.id] = n
        }
        return map
    }

    private func transformResponse(api: NewslettersResponse, originalMap: [Int: Newsletter]?) -> [Newsletter] {
        api.result.map { item in
            let original = originalMap?[item.id]
            return Newsletter(
                id: item.id,
                title: item.title,
                author: item.author,
                sourceId: item.source_id,
                sourceMimeType: item.source_mime_type,
                read: item.read,
                deleted: item.deleted,
                progress: item.progress,
                createdAt: item.created_at,
                updatedAt: item.updated_at,
                epubUpdatedAt: item.epub_updated_at,
                sourceUpdatedAt: item.source_updated_at,
                epubVersion: original?.epubVersion,
                sourceVersion: original?.sourceVersion,
                epubLastAccessedAt: original?.epubLastAccessedAt,
                sourceLastAccessedAt: original?.sourceLastAccessedAt
            )
        }
    }

    private func finishSync() {
        isSyncing = false
        currentSyncTask = nil
    }

    private func iso8601String(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}
