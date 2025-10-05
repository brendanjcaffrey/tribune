import Foundation

enum AuthAPIError: LocalizedError {
    case badStatus(Int)
    case missingJWT

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "Server returned status \(code)."
        case .missingJWT: return "Response missing expected JWT."
        }
    }
}
