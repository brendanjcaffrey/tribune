import Foundation
import Reachability

/// persists user actions (read/unread/delete/progress) and replays them to the
/// server in order. designed to survive offline periods, app suspension, and
/// transient server failures.
@MainActor
final class UpdateManager {
    static let shared = UpdateManager()

    // not private so tests can seed & inspect the queue in storage
    static let storageKey = "updates"

    private let sender: UpdateSending
    private let defaults: UserDefaults
    private let retrySeconds: UInt64

    private(set) var pendingUpdates: [Update] = []
    private var flushTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var reachability: Reachability?

    /// the defaults are all what the app wants. tests inject their own sender,
    /// storage and retry delay, and skip the reachability notifier
    init(
        sender: UpdateSending = APIUpdateSender(),
        defaults: UserDefaults = .standard,
        retrySeconds: UInt64 = 30,
        monitorReachability: Bool = true
    ) {
        self.sender = sender
        self.defaults = defaults
        self.retrySeconds = retrySeconds

        loadPending()
        if monitorReachability {
            setupReachability()
        }
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
        pendingUpdates = (pendingUpdates + [update]).coalesced()
        persist()
        await flush()
    }

    /// drain `pendingUpdates` in order. stops at the first transient failure
    /// and schedules a retry. concurrent callers join the in-flight flush
    /// rather than starting a parallel one. not private so tests can await it.
    func flush() async {
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
                    self.drop(next)
                } catch let error where Self.isPermanent(error) {
                    print("dropping update due to permanent error \(error): \(next)")
                    self.drop(next)
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

    /// remove by value rather than position: a newer update coalesced in while
    /// this one was in flight may have replaced it in the queue, and that
    /// replacement still needs to be sent.
    private func drop(_ update: Update) {
        guard let index = pendingUpdates.firstIndex(of: update) else { return }
        pendingUpdates.remove(at: index)
        persist()
    }

    private func send(_ update: Update) async throws {
        do {
            try await sender.send(update)
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
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            print("UpdateManager persist error: \(error)")
        }
    }

    private func loadPending() {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        let loaded = (try? JSONDecoder().decode([Update].self, from: data)) ?? []
        pendingUpdates = loaded.coalesced()
        if pendingUpdates.count != loaded.count {
            persist()
        }
    }
}
