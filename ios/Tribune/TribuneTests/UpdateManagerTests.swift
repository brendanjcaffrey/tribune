import Foundation
import Testing
@testable import Tribune

/// a stand in for the network. records what it was asked to send, can fail on
/// demand, and can hold a send open so tests can poke the queue mid-flight
@MainActor
final class MockUpdateSender: UpdateSending {
    private(set) var sent: [Update] = []

    /// consumed one per send, in order. a nil entry (or a spent list) succeeds
    var results: [Error?] = []

    /// every send fails with this, once `results` is spent
    var defaultError: Error?

    /// a send of this update blocks until `release()` is called
    var holdUpdate: Update?
    private var holdContinuation: CheckedContinuation<Void, Never>?
    private var released = false

    func send(_ update: Update) async throws {
        sent.append(update)

        if update == holdUpdate && !released {
            await withCheckedContinuation { holdContinuation = $0 }
        }

        if !results.isEmpty {
            if let error = results.removeFirst() {
                throw error
            }
            return
        }

        if let defaultError {
            throw defaultError
        }
    }

    func release() {
        released = true
        holdContinuation?.resume()
        holdContinuation = nil
    }
}

/// a throwaway defaults suite so tests don't tread on the app's (or each
/// other's) stored queue
final class TestDefaults {
    let name = "UpdateManagerTests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: name)
    }
}

@MainActor
struct UpdateManagerTests {
    let storage = TestDefaults()

    // MARK: - helpers

    private func makeManager(
        sender: MockUpdateSender,
        retrySeconds: UInt64 = 3600
    ) -> UpdateManager {
        UpdateManager(
            sender: sender,
            defaults: storage.defaults,
            retrySeconds: retrySeconds,
            monitorReachability: false
        )
    }

    private func seed(_ updates: [Update]) {
        let data = try! JSONEncoder().encode(updates)
        storage.defaults.set(data, forKey: UpdateManager.storageKey)
    }

    private func stored() -> [Update] {
        guard let data = storage.defaults.data(forKey: UpdateManager.storageKey) else { return [] }
        return (try? JSONDecoder().decode([Update].self, from: data)) ?? []
    }

    /// spin (briefly) until `condition` holds, so tests can wait on work that
    /// isn't awaitable - the retry timer, or a flush another task kicked off
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return condition()
    }

    private static let transientError = URLError(.notConnectedToInternet)

    // MARK: - sending

    @Test func sendsEachKindOfUpdate() async {
        let sender = MockUpdateSender()
        let manager = makeManager(sender: sender)

        await manager.markNewsletterAsRead(1)
        await manager.markNewsletterAsUnread(2)
        await manager.markNewsletterAsDeleted(3)
        await manager.updateNewsletterProgress(4, progress: "epubcfi(/6/4)")

        #expect(sender.sent == [
            .read(newsletterId: 1),
            .unread(newsletterId: 2),
            .delete(newsletterId: 3),
            .progress(newsletterId: 4, progress: "epubcfi(/6/4)"),
        ])
        #expect(manager.pendingUpdates.isEmpty)
        #expect(stored().isEmpty)
    }

    @Test func drainsPendingUpdatesFromStorageInOrder() async {
        let updates: [Update] = [
            .read(newsletterId: 1),
            .unread(newsletterId: 2),
            .delete(newsletterId: 3),
            .progress(newsletterId: 4, progress: "a"),
        ]
        seed(updates)

        let sender = MockUpdateSender()
        let manager = makeManager(sender: sender)
        await manager.flush()

        #expect(sender.sent == updates)
        #expect(manager.pendingUpdates.isEmpty)
    }

    @Test func keepsAnUpdateQueuedWhenSendingFailsTransiently() async {
        let sender = MockUpdateSender()
        sender.defaultError = Self.transientError
        let manager = makeManager(sender: sender)

        await manager.markNewsletterAsRead(1)

        #expect(manager.pendingUpdates == [.read(newsletterId: 1)])
        #expect(stored() == [.read(newsletterId: 1)])

        // and it goes out on the next flush
        sender.defaultError = nil
        await manager.flush()
        #expect(manager.pendingUpdates.isEmpty)
        #expect(stored().isEmpty)
    }

    @Test func stopsAtTheFirstTransientFailureAndResumesFifo() async {
        seed([
            .read(newsletterId: 1),
            .unread(newsletterId: 2),
            .delete(newsletterId: 3),
        ])

        let sender = MockUpdateSender()
        sender.results = [nil, Self.transientError]
        sender.defaultError = Self.transientError
        let manager = makeManager(sender: sender)
        await manager.flush()

        // 1 went out, 2 failed, and 3 was never attempted
        #expect(sender.sent == [.read(newsletterId: 1), .unread(newsletterId: 2)])
        #expect(manager.pendingUpdates == [.unread(newsletterId: 2), .delete(newsletterId: 3)])

        sender.defaultError = nil
        await manager.flush()
        #expect(sender.sent.suffix(2) == [.unread(newsletterId: 2), .delete(newsletterId: 3)])
        #expect(manager.pendingUpdates.isEmpty)
    }

    @Test func retriesOnATimerAfterATransientFailure() async {
        let sender = MockUpdateSender()
        sender.results = [Self.transientError]
        let manager = makeManager(sender: sender, retrySeconds: 0)

        await manager.markNewsletterAsRead(1)
        #expect(manager.pendingUpdates == [.read(newsletterId: 1)])

        #expect(await waitUntil { manager.pendingUpdates.isEmpty })
        #expect(sender.sent == [.read(newsletterId: 1), .read(newsletterId: 1)])
    }

    @Test func dropsAnUpdateOnAPermanentFailureAndKeepsDraining() async {
        seed([.read(newsletterId: 1), .read(newsletterId: 2)])

        let sender = MockUpdateSender()
        sender.results = [APIError.badStatus(422)]
        let manager = makeManager(sender: sender)
        await manager.flush()

        #expect(sender.sent == [.read(newsletterId: 1), .read(newsletterId: 2)])
        #expect(manager.pendingUpdates.isEmpty)
    }

    @Test func dropsAnUpdateWhoseNewsletterIsAlreadyGone() async {
        let sender = MockUpdateSender()
        sender.results = [APIError.badStatus(404)]
        let manager = makeManager(sender: sender)

        await manager.markNewsletterAsDeleted(1)

        #expect(sender.sent == [.delete(newsletterId: 1)])
        #expect(manager.pendingUpdates.isEmpty)
    }

    /// 401 might just be a session mid-renewal and 408 is literally a timeout,
    /// so neither is permanent
    @Test(arguments: [401, 408])
    func keepsAnUpdateQueuedOn(status: Int) async {
        let sender = MockUpdateSender()
        sender.defaultError = APIError.badStatus(status)
        let manager = makeManager(sender: sender)

        await manager.markNewsletterAsRead(1)

        #expect(manager.pendingUpdates == [.read(newsletterId: 1)])
    }

    @Test func doesNotDropAnUpdateWhenNotAuthorized() async {
        let sender = MockUpdateSender()
        sender.defaultError = APIError.notAuthorized
        let manager = makeManager(sender: sender)

        await manager.markNewsletterAsRead(1)

        #expect(manager.pendingUpdates == [.read(newsletterId: 1)])
    }

    // MARK: - persistence

    @Test func picksUpWhereAPreviousInstanceLeftOff() async {
        let failing = MockUpdateSender()
        failing.defaultError = Self.transientError
        let first = makeManager(sender: failing)
        await first.markNewsletterAsRead(1)
        #expect(first.pendingUpdates == [.read(newsletterId: 1)])

        let working = MockUpdateSender()
        let second = makeManager(sender: working)
        await second.flush()

        #expect(working.sent == [.read(newsletterId: 1)])
        #expect(second.pendingUpdates.isEmpty)
        #expect(stored().isEmpty)
    }

    @Test func ignoresGarbageInStorage() async {
        storage.defaults.set(Data("not json".utf8), forKey: UpdateManager.storageKey)

        let sender = MockUpdateSender()
        let manager = makeManager(sender: sender)
        await manager.flush()

        #expect(manager.pendingUpdates.isEmpty)
        #expect(sender.sent.isEmpty)
    }

    // MARK: - coalescing

    @Test func coalescesUpdatesQueuedUpWhileOffline() async {
        let sender = MockUpdateSender()
        sender.defaultError = Self.transientError
        let manager = makeManager(sender: sender)

        await manager.markNewsletterAsRead(1)
        await manager.updateNewsletterProgress(1, progress: "a")
        await manager.updateNewsletterProgress(1, progress: "b")
        await manager.markNewsletterAsUnread(1)

        let expected: [Update] = [
            .progress(newsletterId: 1, progress: "b"),
            .unread(newsletterId: 1),
        ]
        #expect(manager.pendingUpdates == expected)
        #expect(stored() == expected)

        // and only the survivors go out once the network is back
        sender.defaultError = nil
        await manager.flush()
        #expect(sender.sent.suffix(2) == expected)
        #expect(manager.pendingUpdates.isEmpty)
    }

    @Test func doesNotCoalesceAcrossNewsletters() async {
        let sender = MockUpdateSender()
        sender.defaultError = Self.transientError
        let manager = makeManager(sender: sender)

        await manager.updateNewsletterProgress(1, progress: "a")
        await manager.updateNewsletterProgress(2, progress: "b")
        await manager.updateNewsletterProgress(1, progress: "c")

        #expect(manager.pendingUpdates == [
            .progress(newsletterId: 2, progress: "b"),
            .progress(newsletterId: 1, progress: "c"),
        ])
    }

    @Test func coalescesPendingUpdatesLoadedFromStorage() async {
        seed([
            .progress(newsletterId: 1, progress: "a"),
            .read(newsletterId: 1),
            .progress(newsletterId: 1, progress: "b"),
        ])

        let sender = MockUpdateSender()
        sender.defaultError = Self.transientError
        let manager = makeManager(sender: sender)

        let expected: [Update] = [
            .read(newsletterId: 1),
            .progress(newsletterId: 1, progress: "b"),
        ]
        #expect(manager.pendingUpdates == expected)
        // the shrunken queue is written back out
        #expect(stored() == expected)
    }

    @Test func stillSendsAnUpdateThatCoalescedOverOneInFlight() async {
        let sender = MockUpdateSender()
        sender.holdUpdate = .progress(newsletterId: 1, progress: "a")
        let manager = makeManager(sender: sender)

        // this doesn't return until the held send does
        let inFlight = Task { await manager.updateNewsletterProgress(1, progress: "a") }
        #expect(await waitUntil { sender.sent == [.progress(newsletterId: 1, progress: "a")] })

        // supersede the update currently on the wire
        let superseding = Task { await manager.updateNewsletterProgress(1, progress: "b") }
        #expect(await waitUntil {
            manager.pendingUpdates == [.progress(newsletterId: 1, progress: "b")]
        })

        sender.release()
        await inFlight.value
        await superseding.value

        #expect(sender.sent == [
            .progress(newsletterId: 1, progress: "a"),
            .progress(newsletterId: 1, progress: "b"),
        ])
        #expect(manager.pendingUpdates.isEmpty)
        #expect(stored().isEmpty)
    }

    // MARK: - the coalescing rule itself

    @Test func coalescingKeepsOnlyTheLastUpdateOfEachKindPerNewsletter() {
        let updates: [Update] = [
            .progress(newsletterId: 123, progress: "a"),
            .read(newsletterId: 123),
            .progress(newsletterId: 123, progress: "b"),
            .unread(newsletterId: 123),
            .progress(newsletterId: 456, progress: "c"),
            .progress(newsletterId: 123, progress: "d"),
        ]

        #expect(updates.coalesced() == [
            .unread(newsletterId: 123),
            .progress(newsletterId: 456, progress: "c"),
            .progress(newsletterId: 123, progress: "d"),
        ])
    }

    @Test func coalescingKeepsUpdatesOfDifferentKindsForTheSameNewsletter() {
        let updates: [Update] = [
            .read(newsletterId: 1),
            .progress(newsletterId: 1, progress: "a"),
            .delete(newsletterId: 1),
        ]

        #expect(updates.coalesced() == updates)
    }

    @Test func coalescingDropsDuplicateDeletes() {
        let updates: [Update] = [
            .delete(newsletterId: 1),
            .delete(newsletterId: 2),
            .delete(newsletterId: 1),
        ]

        #expect(updates.coalesced() == [
            .delete(newsletterId: 2),
            .delete(newsletterId: 1),
        ])
    }

    @Test func coalescingLeavesAnAlreadyCoalescedQueueAlone() {
        let updates: [Update] = [
            .read(newsletterId: 1),
            .progress(newsletterId: 2, progress: "a"),
            .unread(newsletterId: 3),
        ]

        #expect(updates.coalesced() == updates)
        #expect([Update]().coalesced() == [])
    }
}
