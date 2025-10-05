import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: Session

    var body: some View {
        switch session.state {
        case .unknown, .authenticating:
            ProgressView("Loading…")
                .task { /* ensure restore started via Session.init() */ }
        case .unauthenticated:
            LoginView()
        case .authenticated:
            NewsletterView()
        }
    }
}
