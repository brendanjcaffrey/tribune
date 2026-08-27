import Foundation

/// fetches a newsletter's epub or source file. the app goes to the server,
/// tests hand back canned data
@MainActor
protocol NewsletterFileFetching {
    func fetch(type: APIFileType, id: Int) async throws -> Data
}

struct APINewsletterFileFetcher: NewsletterFileFetching {
    // see SystemFileStore for why this isn't the implicit init
    nonisolated init() {}

    func fetch(type: APIFileType, id: Int) async throws -> Data {
        try await APIClient.getNewsletterFile(type: type, id: id)
    }
}
