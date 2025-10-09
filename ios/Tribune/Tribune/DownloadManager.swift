import Foundation
import Combine

@MainActor
class DownloadManager : DownloadManaging, ObservableObject {
    private let library: LibraryProtocol

    private var currentTask: Task<Void, Never>?
    @Published private var isWorking = false
    @Published var currentEpubDownloadId: Int?
    @Published var currentSourceDownloadId: Int?

    init(library: LibraryProtocol) {
        self.library = library
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

    private func checkForDownloadsInner() async throws {
        guard Defaults.getDownloadMode() else { return }

        let newsletters = try await library.getUnreadUndeletedNewsletters()
        for newsletter in newsletters {
            if newsletter.epubVersion != newsletter.epubUpdatedAt {
                try await self.downloadEpub(newsletter: newsletter)
            }
        }
    }

    func downloadEpub(newsletter: Newsletter) async throws {
        guard !Files.fileExists(type: .epub, id: newsletter.id) else { return }
        currentEpubDownloadId = newsletter.id
        defer { currentEpubDownloadId = nil }

        let data = try await APIClient.getNewsletterFile(type: .epub, id: newsletter.id)
        Files.writeFile(type: .epub, id: newsletter.id, data: data)
        newsletter.epubLastAccessedAt = .now
        newsletter.epubVersion = newsletter.epubUpdatedAt
        try library.save()
    }

    func downloadSource(newsletter: Newsletter) async throws {
        guard !Files.fileExists(type: newsletter.sourceFileType, id: newsletter.id) else { return }
        currentSourceDownloadId = newsletter.id
        defer { currentSourceDownloadId = nil }

        let data = try await APIClient.getNewsletterFile(type: .source, id: newsletter.id)
        Files.writeFile(type: newsletter.sourceFileType, id: newsletter.id, data: data)
        newsletter.sourceLastAccessedAt = .now
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
