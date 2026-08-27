import Foundation
@testable import Tribune

/// spin (briefly) until `condition` holds, so tests can wait on work that isn't
/// awaitable - a retry timer, or a task something else kicked off
@MainActor
func waitUntil(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<500 {
        if condition() { return true }
        await Task.yield()
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
    return condition()
}

/// an in memory stand in for the library. `stored` backs the lookups that go by
/// id or recency, while the two query results the download manager asks for are
/// set explicitly, so those tests don't have to model the predicates
@MainActor
final class MockLibrary: LibraryProtocol {
    var stored: [Newsletter] = []
    var unreadUndeleted: [Newsletter] = []
    var withFilesToDelete: [Newsletter] = []

    /// thrown by every read, to exercise the failure paths
    var error: Error?

    private(set) var saveCount = 0
    private(set) var put: [Newsletter] = []

    func hasAnyNewsletters() async throws -> Bool {
        if let error { throw error }
        return !stored.isEmpty
    }

    func getAllNewsletters() async throws -> [Newsletter] {
        if let error { throw error }
        return stored
    }

    func getUnreadUndeletedNewsletters() async throws -> [Newsletter] {
        if let error { throw error }
        return unreadUndeleted
    }

    func getNewslettersWithFilesToDelete() async throws -> [Newsletter] {
        if let error { throw error }
        return withFilesToDelete
    }

    /// newest by updatedAt, with the id as a stable tiebreaker, like the real one
    func getNewestNewsletter() async throws -> Newsletter? {
        if let error { throw error }
        return stored.sorted {
            $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt
        }.first
    }

    func putNewsletter(_ n: Newsletter) async throws {
        if let error { throw error }
        put.append(n)
        if let index = stored.firstIndex(where: { $0.id == n.id }) {
            stored[index] = n
        } else {
            stored.append(n)
        }
    }

    func findById(_ id: Int) async throws -> Newsletter? {
        if let error { throw error }
        return stored.first { $0.id == id }
    }

    func save() throws {
        saveCount += 1
    }

    func lastPut(id: Int) -> Newsletter? {
        put.last { $0.id == id }
    }
}
