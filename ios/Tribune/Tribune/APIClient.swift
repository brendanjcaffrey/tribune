import Foundation

enum APIClient {
    private static let authPath = "/auth"
    private static let keychainService = "com.jcaffrey.tribune.auth"
    private static let keychainAccount = "jwt"

    // POST /auth with form body -> { "jwt": "<token>" }
    static func signIn(username: String, password: String) async throws -> String {
        let url = AppConfig.baseURL.appending(path: authPath)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = formURLEncoded([
            "username": username,
            "password": password
        ]).data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else { throw AuthAPIError.badStatus(code) }

        let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
        guard !auth.jwt.isEmpty else { throw AuthAPIError.missingJWT }

        try Keychain.storeJWT(auth.jwt, service: keychainService, account: keychainAccount)
        return auth.jwt
    }

    // PUT /auth with Authorization: Bearer <jwt> -> { "jwt": "<token>" }
    static func renewAuth() async throws -> String? {
        guard let stored = try Keychain.readJWT(service: keychainService, account: keychainAccount) else {
            return nil
        }
        let url = AppConfig.baseURL.appending(path: authPath)
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(stored)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            // If refresh fails, clear the old token.
            try? Keychain.deleteJWT(service: keychainService, account: keychainAccount)
            throw AuthAPIError.badStatus(code)
        }

        let refreshed = try JSONDecoder().decode(AuthResponse.self, from: data)
        guard !refreshed.jwt.isEmpty else { throw AuthAPIError.missingJWT }

        // Save the new token atomically
        try Keychain.storeJWT(refreshed.jwt, service: keychainService, account: keychainAccount)
        return refreshed.jwt
    }

    static func signOut() {
        try? Keychain.deleteJWT(service: keychainService, account: keychainAccount)
    }

    // Helper to make x-www-form-urlencoded bodies
    private static func formURLEncoded(_ params: [String: String]) -> String {
        params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }
        .joined(separator: "&")
    }
}
