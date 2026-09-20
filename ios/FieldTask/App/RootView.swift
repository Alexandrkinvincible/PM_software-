import SwiftUI

/// The whole of Phase 1's navigation.
///
/// `mustChangePassword` is a state, not a sheet. There is no way past it
/// and nothing behind it to peek at — which is the point of issuing
/// credentials rather than letting people register themselves.
struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        switch session.state {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .signedOut:
            LoginView()

        case .mustChangePassword:
            ChangePasswordView()

        case .ready:
            HomeView()
        }
    }
}
