import Foundation
import Reachability

/// persists user actions (read/unread/delete/progress) and replays them to the
/// server in order. designed to survive offline periods, app suspension, and
/// transient server failures.
@MainActor
final class UpdateManager {
    static let shared = UpdateManager()

    private let storageKey = "updates"
    private let retrySeconds: UInt64 = 30

    private var pendingUpdates: [Update] = []
    private var flushTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var reachability: Reachability?

    private init() {
        loadPending()
        setupReachability()
        flushPending()
    }

    // MARK: - Public API

    func markNewsletterAsRead(_ id: Int) async {
        await enqueue(.read(newsletterId: id))
    }

    func markNewsletterAsUnread(_ id: Int) async {
        await enqueue(.unread(newsletterId: id))
    }

    func markNewsletterAsDeleted(_ id: Int) async {
        await enqueue(.delete(newsletterId: id))
    }

    func updateNewsletterProgress(_ id: Int, progress: String) async {
        await enqueue(.progress(newsletterId: id, progress: progress))
    }

    /// trigger a flush attempt without awaiting it, safe to call from app
    /// foreground hooks, after sync, etc
    func flushPending() {
        Task { await flush() }
    }

    var pendingCount: Int { pendingUpdates.count }

    // MARK: - Internal

    private func enqueue(_ update: Update) async {
        pendingUpdates.append(update)
        persist()
        await flush()
    }

    /// drain `pendingUpdates` in order. stops at the first transient failure
    /// and schedules a retry. concurrent callers join the in-flight flush
    /// rather than starting a parallel one.
    private func flush() async {
        if let existing = flushTask {
            await existing.value
            return
        }

        retryTask?.cancel()
        retryTask = nil

        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            while let next = self.pendingUpdates.first {
                do {
                    try await self.send(next)
                    self.dropFirst()
                } catch let error where Self.isPermanent(error) {
                    print("dropping update due to permanent error \(error): \(next)")
                    self.dropFirst()
                } catch {
                    self.scheduleRetry()
                    return
                }
            }
        }

        flushTask = task
        await task.value
        flushTask = nil
    }

    private func dropFirst() {
        guard !pendingUpdates.isEmpty else { return }
        pendingUpdates.removeFirst()
        persist()
    }

    private func send(_ update: Update) async throws {
        do {
            switch update {
            case .read(let id):
                try await APIClient.newsletterRead(id: id)
            case .unread(let id):
                try await APIClient.newsletterUnread(id: id)
            case .delete(let id):
                try await APIClient.deleteNewsletter(id: id)
            case .progress(let id, let progress):
                try await APIClient.newsletterProgress(id: id, progress: progress)
            }
        } catch APIError.badStatus(404) {
            // should only happen when a newsletter is deleted already, so drop the update
        }
    }

    /// a failure is permanent if it will always fail - so drop the update
    /// 401/408 are also retried — 401 in case the session is being renewed,
    /// 408 because it's literally a timeout
    private static func isPermanent(_ error: Error) -> Bool {
        if let api = error as? APIError {
            switch api {
            case .badStatus(let code):
                return (400..<500).contains(code) && code != 401 && code != 408
            case .notAuthorized:
                return false
            }
        }
        return false
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self, retrySeconds] in
            try? await Task.sleep(nanoseconds: retrySeconds * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            // clear the ref before flushing so a future scheduleRetry from the flush itself can replace us cleanly.
            self.retryTask = nil
            await self.flush()
        }
    }

    private func setupReachability() {
        guard let r = try? Reachability() else { return }
        r.whenReachable = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flushPending()
            }
        }
        try? r.startNotifier()
        reachability = r
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(pendingUpdates)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("UpdateManager persist error: \(error)")
        }
    }

    private func loadPending() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        pendingUpdates = (try? JSONDecoder().decode([Update].self, from: data)) ?? []
    }
}
