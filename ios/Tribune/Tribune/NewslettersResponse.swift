import Foundation

struct NewslettersResponse: Codable {
    struct Item: Codable {
        let id: Int
        let title: String
        let author: String
        let source_mime_type: String
        let read: Bool
        let deleted: Bool
        let progress: String
        let created_at: Date
        let updated_at: String
        let epub_updated_at: String
    }
    let result: [Item]
}
