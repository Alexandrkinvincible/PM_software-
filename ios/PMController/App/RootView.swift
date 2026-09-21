import SwiftUI

/// The whole of Phase 1's navigation.
///
/// `mustChangePassword` is a state, not a sheet. There is no way past it
/// and nothing behind it to peek at — which is the point of issuing
/// credentials rather than letting people register themselves.
struct RootView: View {
    @EnvironmentObject private var session

    var body: some View {
        switch session.state {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .unconfigured:
            SetupNeededView()

        case .signedOut:
            LoginView()

        case .mustChangePassword:
            ChangePasswordView()

        case .ready:
            HomeView()
        }
    }
}

/// Shown when the build has no Supabase project behind it. A login form
/// that can only ever fail is worse than saying what is missing.
struct SetupNeededView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Not connected yet")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("This build has no Supabase project behind it, so there is nothing to sign in to.")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                step(1, "Copy Config.example.xcconfig to Config.xcconfig")
                step(2, "Fill in SUPABASE_URL and SUPABASE_ANON_KEY")
                step(3, "Build again")
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: FT.radius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )

            Text("The anon key is the only key this app should ever hold. A service-role key here would bypass every access rule in the database.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(FT.gutter)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            Text("\(n)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.ftAccent))
            Text(text)
                .font(.system(size: 15, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// #Preview is an iOS 17 macro. PreviewProvider is the portable
// spelling and gives the same canvases in Xcode.
struct PMControllerPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            HomeView()
                .environmentObject(Session.preview())
                .previewDisplayName("Home — Super")

            HomeView()
                .environmentObject(
                    Session.preview(user: PreviewData.lead,
                                    memberships: PreviewData.leadMemberships)
                )
                .previewDisplayName("Home — Lead")

            LoginView()
                .environmentObject(Session.preview(state: .signedOut))
                .previewDisplayName("Sign in")

            ChangePasswordView()
                .environmentObject(Session.preview(state: .mustChangePassword))
                .previewDisplayName("First login")

            SetupNeededView()
                .previewDisplayName("Not connected")
        }
        .previewDevice("iPad Pro (12.9-inch) (6th generation)")
    }
}
