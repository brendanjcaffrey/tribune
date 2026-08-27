/// the transport an `UpdateManager` replays queued updates over. the real one
/// talks to the server, tests substitute their own
@MainActor
protocol UpdateSending {
    func send(_ update: Update) async throws
}

struct APIUpdateSender: UpdateSending {
    // the protocol is main actor isolated, so the implicit init would be too,
    // which the default argument in UpdateManager's init can't call
    nonisolated init() {}

    func send(_ update: Update) async throws {
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
    }
}
