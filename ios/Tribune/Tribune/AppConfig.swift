import Foundation

enum AppConfig {
    static let baseURL: URL = {
        guard
            let p = Bundle.main.object(forInfoDictionaryKey: "API_PROTOCOL") as? String,
            let h = Bundle.main.object(forInfoDictionaryKey: "API_HOST") as? String,
            let url = URL(string: "\(p)://\(h)")
        else { fatalError("Missing or invalid API_PROTOCOL/API_HOST") }
        return url
    }()
}
