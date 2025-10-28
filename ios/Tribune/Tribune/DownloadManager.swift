import Foundation
import Combine
import Reachability

@MainActor
class DownloadManager : DownloadManaging, ObservableObject {
    private let library: LibraryProtocol
    private let reachability: Reachability
    private var onWifi: Bool = false

    private var currentTask: Task<Void, Never>?
    @Published private var isWorking = false
    @Published var currentEpubDownloadId: Int?
    @Published var currentSourceDownloadId: Int?

    init(library: LibraryProtocol) {
        self.library = library
        self.reachability = try! Reachability()
        self.reachability.whenReachable = { reachability in
            self.onWifi = reachability.connection == .wifi
            if self.onWifi {
                Task { await self.checkForDownloads() }
            } else if Defaults.getDownloadMode() && !Defaults.getDownloadOnCellular() {
                self.reset()
            }
        }
        self.reachability.whenUnreachable = { _ in
            self.onWifi = false
            if Defaults.getDownloadMode() && !Defaults.getDownloadOnCellular() {
                self.reset()
            }
        }

        try! self.reachability.startNotifier()
    }

    deinit {
        self.reachability.stopNotifier()
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
        if isWorking && !Defaults.getDownloadMode() {
            reset()
        } else if isWorking && Defaults.getDownloadMode() && !Defaults.getDownloadOnCellular() && !onWifi {
            reset()
        }
    }

    private func checkForDownloadsInner() async throws {
        guard Defaults.getDownloadMode() else { return }
        if !Defaults.getDownloadOnCellular() && !onWifi { return }

        let newsletters = try await library.getUnreadUndeletedNewsletters()
        for newsletter in newsletters {
            if newsletter.epubVersion != newsletter.epubUpdatedAt {
                try await self.downloadEpub(newsletter: newsletter)
            }
        }
    }

    func downloadEpub(newsletter: Newsletter) async throws {
        var exists = Files.fileExists(type: .epub, id: newsletter.id)
        if newsletter.epubVersion != newsletter.epubUpdatedAt {
            exists = false
        }
        if exists { return }

        currentEpubDownloadId = newsletter.id
        defer { currentEpubDownloadId = nil }

        let data = try await APIClient.getNewsletterFile(type: .epub, id: newsletter.id)
        Files.writeFile(type: .epub, id: newsletter.id, data: data)
        newsletter.epubLastAccessedAt = .now
        newsletter.epubVersion = newsletter.epubUpdatedAt
        try library.save()
    }

    func downloadSource(newsletter: Newsletter) async throws {
        var exists = Files.fileExists(type: newsletter.sourceFileType, id: newsletter.id)
        if newsletter.sourceVersion != newsletter.sourceUpdatedAt {
            exists = false
        }
        if exists { return }

        currentSourceDownloadId = newsletter.id
        defer { currentSourceDownloadId = nil }

        let data = try await APIClient.getNewsletterFile(type: .source, id: newsletter.id)
        Files.writeFile(type: newsletter.sourceFileType, id: newsletter.id, data: data)
        newsletter.sourceLastAccessedAt = .now
        newsletter.sourceVersion = newsletter.sourceUpdatedAt
        try library.save()
    }

    private func checkForDeletesInner() async throws {
        let newsletters = try await library.getNewslettersWithFilesToDelete()
        for newsletter in newsletters {
            if shouldDelete(date: newsletter.epubLastAccessedAt) {
                Files.deleteFile(type: .epub, id: newsletter.id)
                newsletter.epubLastAccessedAt = nil
                newsletter.epubVersion = nil
                try library.save()
            }
            if shouldDelete(date: newsletter.sourceLastAccessedAt) {
                Files.deleteFile(type: newsletter.sourceFileType, id: newsletter.id)
                newsletter.sourceLastAccessedAt = nil
                newsletter.sourceVersion = nil
                try library.save()
            }
        }
    }

    private func shouldDelete(date: Date?) -> Bool {
        guard let date = date else { return false }
        return date.timeIntervalSinceNow > 3*24*60*60
    }

    private func finishWork() {
        isWorking = false
        currentTask = nil
    }
}
