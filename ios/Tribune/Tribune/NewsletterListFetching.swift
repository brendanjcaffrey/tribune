import Foundation

/// fetches newsletter metadata from the server. tests hand back canned pages
@MainActor
protocol NewsletterListFetching {
    func fetchAll() async throws -> NewslettersResponse
    func fetchAfter(newsletter: Newsletter) async throws -> NewslettersResponse
}

struct APINewsletterListFetcher: NewsletterListFetching {
    // see SystemFileStore for why this isn't the implicit init
    nonisolated init() {}

    func fetchAll() async throws -> NewslettersResponse {
        try await APIClient.getNewsletters()
    }

    func fetchAfter(newsletter: Newsletter) async throws -> NewslettersResponse {
        try await APIClient.getNewslettersAfter(newsletter: newsletter)
    }
}
