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
        state = .authenticating
        Task {
            do {
                let jwt = try await APIClient.renewAuth()
                self.state = .authenticated(jwt: jwt)
            } catch {
                self.errorMessage = error.localizedDescription
                self.state = .unauthenticated
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
