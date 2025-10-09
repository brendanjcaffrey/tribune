import Foundation

@MainActor
class UpdateManager {
    private(set) var pendingUpdatesFetched = false
    private(set) var pendingUpdates: [Update] = []
    private(set) var attemptingBulkUpdates = false

    private let retryMillis: UInt64 = 30_000 // 30 seconds
    private let storageKey = "updates"

    private var retryTask: Task<Void, Never>? = nil

    static let shared = UpdateManager()

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            do {
                pendingUpdates = try JSONDecoder().decode([Update].self, from: data)
            } catch {
                pendingUpdates = []
            }
        }
        pendingUpdatesFetched = true

        // Try to flush on startup
        Task { await attemptUpdates() }
    }

    func getPendingUpdatesFetched() -> Bool { pendingUpdatesFetched }
    func getPendingUpdates() -> [Update] { pendingUpdates }
    func isAttemptingBulkUpdates() -> Bool { attemptingBulkUpdates }

    func markNewsletterAsRead(_ newsletterId: Int) async {
        await handleUpdate(.read(newsletterId: newsletterId))
    }

    func markNewsletterAsUnread(_ newsletterId: Int) async {
        await handleUpdate(.unread(newsletterId: newsletterId))
    }

    func markNewsletterAsDeleted(_ newsletterId: Int) async {
        await handleUpdate(.delete(newsletterId: newsletterId))
    }

    func updateNewsletterProgress(_ newsletterId: Int, progress: String) async {
        await handleUpdate(.progress(newsletterId: newsletterId, progress: progress))
    }

    private func handleUpdate(_ update: Update) async {
        if !pendingUpdates.isEmpty {
            await addPendingUpdate(update)
            return
        }

        do {
            try await attemptUpdate(update)
        } catch {
            await addPendingUpdate(update)
        }
    }

    private func addPendingUpdate(_ update: Update) async {
        pendingUpdates.append(update)
        persistUpdates()
        scheduleRetry()
    }

    private func attemptUpdate(_ update: Update) async throws {
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
        } catch {
            if case APIError.badStatus(404) = error {
                // silently ignore
            } else {
                throw error
            }
        }
    }

    private func attemptUpdates() async {
        retryTask?.cancel()
        retryTask = nil

        guard pendingUpdatesFetched,
              !attemptingBulkUpdates,
              !pendingUpdates.isEmpty else {
            return
        }

        attemptingBulkUpdates = true
        var idx = 0
        while idx < pendingUpdates.count {
            let update = pendingUpdates[idx]
            do {
                try await attemptUpdate(update)
                pendingUpdates.remove(at: idx)
            } catch {
                // Could not send this one; keep it and move to the next.
                idx += 1
            }
            persistUpdates()
        }
        attemptingBulkUpdates = false

        scheduleRetry()
    }

    private func persistUpdates() {
        do {
            let data = try JSONEncoder().encode(pendingUpdates)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Persist error: \(error)")
        }
    }

    private func scheduleRetry() {
        guard retryTask == nil, !pendingUpdates.isEmpty else { return }
        retryTask = Task { [retryMillis] in
            try? await Task.sleep(nanoseconds: retryMillis * 1_000_000)
            await attemptUpdates()
        }
    }
}
