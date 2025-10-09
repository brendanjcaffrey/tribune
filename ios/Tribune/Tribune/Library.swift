import Foundation
import SwiftData

final class Library: LibraryProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func hasAnyNewsletters() async throws -> Bool {
        var fetch = FetchDescriptor<Newsletter>()
        fetch.fetchLimit = 1
        return try context.fetch(fetch).isEmpty == false
    }

    @MainActor
    func getAllNewsletters() async throws -> [Newsletter] {
        let fetch = FetchDescriptor<Newsletter>()
        return try context.fetch(fetch)
    }

    @MainActor
    func getUnreadUndeletedNewsletters() async throws -> [Newsletter] {
        var fetch = FetchDescriptor<Newsletter>()
        fetch.predicate = #Predicate { n in
            n.deleted == false && n.read == false
        }
        fetch.sortBy = [
            .init(\.createdAt, order: .forward),  // oldest first
            .init(\.id, order: .forward)          // stable tiebreaker
        ]
        return try context.fetch(fetch)
    }

    @MainActor
    func getNewslettersWithFilesToDelete() async throws -> [Newsletter] {
        var fetch = FetchDescriptor<Newsletter>()
        fetch.predicate = #Predicate { n in
            (n.deleted == true || n.read == true) &&
            (n.epubLastAccessedAt != nil || n.sourceLastAccessedAt != nil)
        }
        return try context.fetch(fetch)
    }

    @MainActor
    func getNewestNewsletter() async throws -> Newsletter? {
        var fetch = FetchDescriptor<Newsletter>()
        fetch.sortBy = [
            .init(\.updatedAt, order: .reverse),  // newest first
            .init(\.id, order: .forward)          // stable tiebreaker
        ]
        fetch.fetchLimit = 1
        return try context.fetch(fetch).first
    }

    @MainActor
    func putNewsletter(_ n: Newsletter) async throws {
        // If exists, update; else insert
        if let existing = try await findById(n.id) {
            // update fields
            existing.title = n.title
            existing.author = n.author
            existing.sourceFileType = n.sourceFileType
            existing.read = n.read
            existing.deleted = n.deleted
            existing.progress = n.progress
            existing.createdAt = n.createdAt
            existing.updatedAt = n.updatedAt
            existing.epubUpdatedAt = n.epubUpdatedAt
            existing.epubVersion = n.epubVersion
            existing.epubLastAccessedAt = n.epubLastAccessedAt
            existing.sourceLastAccessedAt = n.sourceLastAccessedAt
        } else {
            context.insert(n)
        }
        try context.save()
    }

    @MainActor
    func findById(_ id: Int) async throws -> Newsletter? {
        var fetch = FetchDescriptor<Newsletter>(
            predicate: #Predicate { $0.id == id },
        )
        fetch.fetchLimit = 1
        let res = try context.fetch(fetch)
        return res.first
    }

    @MainActor
    func markNewsletterRead(_ n: Newsletter) async throws {
        n.read = true
        try save()
        await UpdateManager.shared.markNewsletterAsRead(n.id)
    }

    @MainActor
    func markNewsletterUnread(_ n: Newsletter) async throws {
        n.read = false
        try save()
        await UpdateManager.shared.markNewsletterAsUnread(n.id)
    }

    @MainActor
    func markNewsletterDeleted(_ n: Newsletter) async throws {
        n.deleted = true
        try save()
        await UpdateManager.shared.markNewsletterAsDeleted(n.id)
    }

    @MainActor
    func updateNewsletterProgress(_ n: Newsletter, progress: String) async throws {
        n.progress = progress
        try save()
        await UpdateManager.shared.updateNewsletterProgress(n.id, progress: progress)
    }

    @MainActor
    func save() throws {
        try context.save()
    }
}
