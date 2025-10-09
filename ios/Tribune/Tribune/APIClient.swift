import Foundation

enum APIClient {
    private static let authPath = "/auth"
    private static let newslettersPath = "/newsletters"
    private static let keychainService = "com.jcaffrey.tribune.auth"
    private static let keychainAccount = "jwt"

    private static func getToken() throws -> String? {
        return try Keychain.readJWT(service: keychainService, account: keychainAccount)
    }

    static func hasToken() -> Bool {
        do {
            let token = try getToken()
            print("token: \(token ?? "nil")")
            return token != nil && token != ""
        } catch {
            return false
        }
    }

    // POST /auth
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
        guard (200..<300).contains(code) else { throw APIError.badStatus(code) }

        let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
        try Keychain.storeJWT(auth.jwt, service: keychainService, account: keychainAccount)
        return auth.jwt
    }

    // PUT /auth
    static func renewAuth() async throws -> String {
        guard let stored = try getToken() else {
            throw APIError.notAuthorized
        }
        let url = AppConfig.baseURL.appending(path: authPath)
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(stored)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            try? Keychain.deleteJWT(service: keychainService, account: keychainAccount)
            throw APIError.badStatus(code)
        }

        let refreshed = try JSONDecoder().decode(AuthResponse.self, from: data)
        try Keychain.storeJWT(refreshed.jwt, service: keychainService, account: keychainAccount)
        return refreshed.jwt
    }

    static func signOut() {
        try? Keychain.deleteJWT(service: keychainService, account: keychainAccount)
    }

    // GET /newsletters
    static func getNewsletters() async throws -> NewslettersResponse {
        guard let stored = try getToken() else {
            throw APIError.notAuthorized
        }
        let url = AppConfig.baseURL.appending(path: newslettersPath)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(stored)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            throw APIError.badStatus(code)
        }

        return try Self.buildDecoder().decode(NewslettersResponse.self, from: data)
    }

    static func getNewslettersAfter(newsletter: Newsletter) async throws -> NewslettersResponse {
        guard let stored = try getToken() else {
            throw APIError.notAuthorized
        }
        var components = URLComponents()
        components.scheme = AppConfig.apiProtocol
        if AppConfig.apiHost.contains(":") {
            let parts = AppConfig.apiHost.split(separator: ":").map(String.init)
            guard parts.count == 2 else { fatalError("couldn't split \(AppConfig.apiHost) into host and port") }
            guard let port = parts.last.flatMap(Int.init) else { fatalError("couldn't parse port from \(AppConfig.apiHost)") }
            components.host = String(parts.first!)
            components.port = port
        } else {
            components.host = AppConfig.apiHost
        }
        components.path = newslettersPath
        components.queryItems = [
            URLQueryItem(name: "after_timestamp", value: newsletter.updatedAt),
            URLQueryItem(name: "after_id", value: String(newsletter.id))
        ]
        // the server is interpreting +00 at the end of the timestamp as [space]00, so let's replace that ourselves
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")

        var req = URLRequest(url: components.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(stored)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            throw APIError.badStatus(code)
        }

        return try Self.buildDecoder().decode(NewslettersResponse.self, from: data)
    }

    // GET /newsletters/:id/:type
    static func getNewsletterFile(type: FileType, id: Int) async throws -> Data {
        guard let stored = try getToken() else {
            throw APIError.notAuthorized
        }
        let url = AppConfig.baseURL.appending(path: newslettersPath).appending(path: "/\(id)/\(type)")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(stored)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            throw APIError.badStatus(code)
        }

        return data
    }

    private static func formURLEncoded(_ params: [String: String]) -> String {
        params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }
        .joined(separator: "&")
    }

    private static func buildDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = formatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "Invalid date: \(dateString)")
        }
        return decoder
    }
}
