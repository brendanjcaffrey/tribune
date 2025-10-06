import Foundation
import Combine

enum SyncStatus {
    case success
    case error(String)
    case blocked
}

@MainActor
final class SyncManager: ObservableObject {
    private let library: LibraryProtocol
    private weak var downloadManager: DownloadManaging?

    private var currentSyncTask: Task<SyncStatus, Never>?
    @Published private var isSyncing = false

    init(library: LibraryProtocol, downloadManager: DownloadManaging?) {
        self.library = library
        self.downloadManager = downloadManager
    }

    func reset() {
        currentSyncTask?.cancel()
        currentSyncTask = nil
    }

    func syncLibrary() async -> SyncStatus {
        // prevent overlapping runs (actor serializes, but this guards re-entrancy if awaited within)
        guard !isSyncing else { return .blocked }

        if currentSyncTask != nil { fatalError() }
        isSyncing = true

        currentSyncTask = Task { [weak self] in
            guard let self else { return SyncStatus.blocked }
            defer { Task { await self.finishSyncAndSchedule() } }

            do {
                if try await library.hasAnyNewsletters() {
                    try await fetchUpdates()
                } else {
                    try await fetchInitial()
                }

                Task { self.downloadManager?.checkForDownloads() }
                return SyncStatus.success
            } catch is CancellationError {
                return SyncStatus.blocked
                // Silently ignore if we cancelled on purpose
            } catch {
                return SyncStatus.error(error.localizedDescription)
            }
        }

        return await currentSyncTask?.value ?? .blocked
    }

    private func fetchInitial() async throws {
        let response = try await APIClient.getNewsletters()

        for n in transformResponse(api: response, originalMap: .none) {
            try await library.putNewsletter(n)
        }
    }

    private func fetchUpdates(fetchedAny: Bool = false) async throws {
        let newsletter = try await library.getNewestNewsletter()
        guard let newsletter = newsletter else { return }

        let response = try await APIClient.getNewslettersAfter(newsletter: newsletter)
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
                sourceMimeType: item.source_mime_type,
                read: item.read,
                deleted: item.deleted,
                progress: item.progress,
                createdAt: item.created_at,
                updatedAt: item.updated_at,
                epubUpdatedAt: item.epub_updated_at,
                epubVersion: original?.epubVersion,
                epubLastAccessedAt: original?.epubLastAccessedAt,
                sourceLastAccessedAt: original?.sourceLastAccessedAt
            )
        }
    }

    private func finishSyncAndSchedule() async {
        isSyncing = false
        currentSyncTask = nil
    }

    private func iso8601String(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}
