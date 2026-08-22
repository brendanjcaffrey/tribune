import Foundation
import SwiftData

@Model
public final class Newsletter {
    @Attribute(.unique)
    public var id: Int
    public var title: String
    public var author: String
    public var sourceId: String?
    public var sourceFileType: FileType
    public var read: Bool
    public var deleted: Bool
    public var progress: String
    // createdAt is displayed, so having it parsed already as a Date is nice
    public var createdAt: Date
    // updatedAt/epubUpdatedAt/sourceUpdatedAt need absolute precision, so keep as strings
    public var updatedAt: String
    public var epubUpdatedAt: String
    public var sourceUpdatedAt: String
    /// These are nil if never downloaded and will match `[epub|source]UpdatedAt` once downloaded
    public var epubVersion: String?
    public var sourceVersion: String?
    /// These are set to the time it was first downloaded (on download) and updated whenever the file is opened
    /// This is used to decide when to delete old files
    public var epubLastAccessedAt: Date?
    public var sourceLastAccessedAt: Date?

    public init(
        id: Int,
        title: String,
        author: String,
        sourceId: String?,
        sourceMimeType: String,
        read: Bool,
        deleted: Bool,
        progress: String,
        createdAt: Date,
        updatedAt: String,
        epubUpdatedAt: String,
        sourceUpdatedAt: String,
        epubVersion: String? = nil,
        sourceVersion: String? = nil,
        epubLastAccessedAt: Date? = nil,
        sourceLastAccessedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.sourceId = sourceId
        self.sourceFileType = Files.mimeToFileType(sourceMimeType)
        self.read = read
        self.deleted = deleted
        self.progress = progress
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.epubUpdatedAt = epubUpdatedAt
        self.sourceUpdatedAt = sourceUpdatedAt
        self.epubVersion = epubVersion
        self.sourceVersion = sourceVersion
        self.epubLastAccessedAt = epubLastAccessedAt
        self.sourceLastAccessedAt = sourceLastAccessedAt
    }

    /// the source id is a url when the newsletter came from a saved web page, so it can be
    /// opened in the browser. emails and the like use other schemes, which aren't openable
    public var sourceURL: URL? {
        guard let sourceId, let url = URL(string: sourceId) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        guard url.host?.isEmpty == false else { return nil }
        return url
    }

    // yyyy-MM-dd hh:mm am/pm in local time, with lowercase am/pm
    static let displayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = .current
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd hh:mm a"   // 12-hour clock with am/pm
        df.amSymbol = "am"
        df.pmSymbol = "pm"
        return df
    }()
}
