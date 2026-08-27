import Foundation

enum Update: Codable, Equatable {
    case read(newsletterId: Int)
    case unread(newsletterId: Int)
    case delete(newsletterId: Int)
    case progress(newsletterId: Int, progress: String)

    private enum CodingKeys: String, CodingKey { case type, newsletterId, progress }
    private enum Kind: String, Codable { case read, unread, delete, progress }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .type)
        let id   = try c.decode(Int.self, forKey: .newsletterId)
        switch kind {
        case .read:     self = .read(newsletterId: id)
        case .unread:   self = .unread(newsletterId: id)
        case .delete:   self = .delete(newsletterId: id)
        case .progress: self = .progress(newsletterId: id, progress: try c.decode(String.self, forKey: .progress))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .read(let id):
            try c.encode(Kind.read, forKey: .type)
            try c.encode(id, forKey: .newsletterId)
        case .unread(let id):
            try c.encode(Kind.unread, forKey: .type)
            try c.encode(id, forKey: .newsletterId)
        case .delete(let id):
            try c.encode(Kind.delete, forKey: .type)
            try c.encode(id, forKey: .newsletterId)
        case .progress(let id, let value):
            try c.encode(Kind.progress, forKey: .type)
            try c.encode(id, forKey: .newsletterId)
            try c.encode(value, forKey: .progress)
        }
    }

    var typeString: String {
        switch self {
        case .read: return "read"
        case .unread: return "unread"
        case .delete: return "delete"
        case .progress: return "progress"
        }
    }

    var newsletterId: Int {
        switch self {
        case .read(let id), .unread(let id), .delete(let id): return id
        case .progress(let id, _): return id
        }
    }
}

extension Update {
    /// updates of the same kind for the same newsletter supersede each other,
    /// so they share a key. read & unread are the same piece of state, so the
    /// later one wins.
    var coalesceKey: String {
        switch self {
        case .read(let id), .unread(let id): return "read:\(id)"
        case .delete(let id): return "delete:\(id)"
        case .progress(let id, _): return "progress:\(id)"
        }
    }
}

extension Array where Element == Update {
    /// keep only the newest update of each kind per newsletter, preserving
    /// order. a burst of progress updates (or a read/unread flip flop) piled up
    /// while offline collapses to whatever state the user ended up with, since
    /// that's all the server cares about.
    func coalesced() -> [Update] {
        var seen = Set<String>()
        var result: [Update] = []
        for update in reversed() where seen.insert(update.coalesceKey).inserted {
            result.append(update)
        }
        return result.reversed()
    }
}
