import Foundation

enum APIError: LocalizedError {
    case notAuthorized
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "User not authorized"
        case .badStatus(let code): return "Server returned status \(code)"
        }
    }
}
