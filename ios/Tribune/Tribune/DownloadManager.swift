import Foundation
import Combine
import Reachability

@MainActor
class DownloadManager : DownloadManaging, ObservableObject {
    /// downloaded files go once they haven't been opened in this long
    static let deleteFilesAfter: TimeInterval = 3*24*60*60

    private let library: LibraryProtocol
    private let settings: DownloadSettings
    private let files: FileStoring
    private let fetcher: NewsletterFileFetching
    private let reachability: Reachability?
    private(set) var onWifi: Bool = false

    // not private so tests can await a pass they cancelled
    private(set) var currentTask: Task<Void, Never>?
    @Published private var isWorking = false
    @Published var currentEpubDownloadId: Int?
    @Published var currentSourceDownloadId: Int?

    /// everything but the library defaults to what the app wants. tests inject
    /// their own settings, storage and fetcher, and skip the reachability
    /// notifier so they can drive the network state themselves
    init(
        library: LibraryProtocol,
        settings: DownloadSettings = UserDownloadSettings(),
        files: FileStoring = SystemFileStore(),
        fetcher: NewsletterFileFetching = APINewsletterFileFetcher(),
        monitorReachability: Bool = true
    ) {
        self.library = library
        self.settings = settings
        self.files = files
        self.fetcher = fetcher
        self.reachability = monitorReachability ? try! Reachability() : nil

        self.reachability?.whenReachable = { reachability in
            self.networkChanged(onWifi: reachability.connection == .wifi)
        }
        self.reachability?.whenUnreachable = { _ in
            self.networkChanged(onWifi: false)
        }

        try! self.reachability?.startNotifier()
    }

    deinit {
        self.reachability?.stopNotifier()
    }

    /// the network came or went. downloading resumes on wifi, and stops if the
    /// user only wanted to download on wifi and we just lost it
    func networkChanged(onWifi: Bool) {
        self.onWifi = onWifi
        if onWifi {
            Task { await self.checkForDownloads() }
        } else if settings.downloadMode && !settings.downloadOnCellular {
            reset()
        }
    }

    func reset() {
        currentTask?.cancel()
        currentTask = nil
    }

    func checkForDownloads() async {
        guard !isWorking else { return }

        if currentTask != nil { fatalError() }
        isWorking = true

        currentTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishWork() }

            do {
                try await checkForDownloadsInner()
                try await checkForDeletesInner()
            } catch is CancellationError {
                // do nothing
            } catch {
                print(error.localizedDescription)
            }
        }
    }

    func checkIfCancelNeeded() {
        if isWorking && !settings.downloadMode {
            reset()
        } else if isWorking && settings.downloadMode && !settings.downloadOnCellular && !onWifi {
            reset()
        }
    }

    /// wait for any in flight work to finish. `checkForDownloads` kicks the
    /// work off and returns, so tests need this to know when it's done
    func waitForCurrentWork() async {
        await currentTask?.value
    }

    private func checkForDownloadsInner() async throws {
        guard settings.downloadMode else { return }
        if !settings.downloadOnCellular && !onWifi { return }

        let newsletters = try await library.getUnreadUndeletedNewsletters()
        for newsletter in newsletters {
            if newsletter.epubVersion != newsletter.epubUpdatedAt {
                try await self.downloadEpub(newsletter: newsletter)
            }
        }
    }

    func downloadEpub(newsletter: Newsletter) async throws {
        var exists = files.fileExists(type: .epub, id: newsletter.id)
        if newsletter.epubVersion != newsletter.epubUpdatedAt {
            exists = false
        }
        if exists { return }

        currentEpubDownloadId = newsletter.id
        defer { currentEpubDownloadId = nil }

        let data = try await fetcher.fetch(type: .epub, id: newsletter.id)
        files.writeFile(type: .epub, id: newsletter.id, data: data)
        newsletter.epubLastAccessedAt = .now
        newsletter.epubVersion = newsletter.epubUpdatedAt
        try library.save()
    }

    func downloadSource(newsletter: Newsletter) async throws {
        var exists = files.fileExists(type: newsletter.sourceFileType, id: newsletter.id)
        if newsletter.sourceVersion != newsletter.sourceUpdatedAt {
            exists = false
        }
        if exists { return }

        currentSourceDownloadId = newsletter.id
        defer { currentSourceDownloadId = nil }

        let data = try await fetcher.fetch(type: .source, id: newsletter.id)
        files.writeFile(type: newsletter.sourceFileType, id: newsletter.id, data: data)
        newsletter.sourceLastAccessedAt = .now
        newsletter.sourceVersion = newsletter.sourceUpdatedAt
        try library.save()
    }

    private func checkForDeletesInner() async throws {
        let newsletters = try await library.getNewslettersWithFilesToDelete()
        for newsletter in newsletters {
            if shouldDelete(date: newsletter.epubLastAccessedAt) {
                files.deleteFile(type: .epub, id: newsletter.id)
                newsletter.epubLastAccessedAt = nil
                newsletter.epubVersion = nil
                try library.save()
            }
            if shouldDelete(date: newsletter.sourceLastAccessedAt) {
                files.deleteFile(type: newsletter.sourceFileType, id: newsletter.id)
                newsletter.sourceLastAccessedAt = nil
                newsletter.sourceVersion = nil
                try library.save()
            }
        }
    }

    private func shouldDelete(date: Date?) -> Bool {
        guard let date = date else { return false }
        // the interval is negative for a past access, which is the only case
        // that can be stale
        return -date.timeIntervalSinceNow > Self.deleteFilesAfter
    }

    private func finishWork() {
        isWorking = false
        currentTask = nil
    }
}
