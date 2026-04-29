import Combine
import Foundation

@MainActor
final class Session: ObservableObject {
    enum State: Equatable {
        case unknown
        case unauthenticated
        case authenticating
        case authenticated(jwt: String)
    }

    @Published var state: State = .unknown
    @Published var errorMessage: String?

    init() {
        restore()
    }

    func restore() {
        guard APIClient.hasToken() else {
            state = .unauthenticated
            return
        }

        // if there's a cached token, assume the user is logged in for offline mode
        state = .authenticated(jwt: "")
        Task {
            do {
                let jwt = try await APIClient.renewAuth()
                self.state = .authenticated(jwt: jwt)
            } catch APIError.badStatus(401), APIError.badStatus(403) {
                self.errorMessage = "Session expired"
                self.state = .unauthenticated
            } catch {
                // ignore a potential network hiccup
                print("renewAuth deferred: \(error.localizedDescription)")
            }
        }
    }

    func signIn(username: String, password: String) {
        state = .authenticating
        errorMessage = nil
        Task {
            do {
                let jwt = try await APIClient.signIn(username: username, password: password)
                self.state = .authenticated(jwt: jwt)
            } catch {
                self.state = .unauthenticated
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func signOut() {
        APIClient.signOut()
        state = .unauthenticated
    }
}
