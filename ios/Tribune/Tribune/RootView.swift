import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: Session

    var body: some View {
        switch session.state {
        case .unknown, .authenticating:
            ProgressView("Loading…")
        case .unauthenticated:
            LoginView()
        case .authenticated:
            NavigationView {
                MainView()
            }
        }
    }
}
