import Foundation

enum ShareError: LocalizedError {
    case noPage
    case notSignedIn
    case badStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .noPage:
            return "Couldn't read this page. Share from Safari to push an article."
        case .notSignedIn:
            return "Open Tribune and sign in first."
        case .badStatus(let code, let body):
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "Server returned status \(code)" : "\(detail) (\(code))"
        }
    }
}
