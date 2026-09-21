import SwiftUI

/// First login. The issued password is a delivery mechanism, not a
/// credential — this screen is the only thing in the app until it is gone.
struct ChangePasswordView: View {
    @EnvironmentObject private var session: Session
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isWorking = false

    /// Deliberately short. A crew will write a long one on a hard hat.
    private let minimumLength = 8

    private var tooShort: Bool { !password.isEmpty && password.count < minimumLength }
    private var mismatch: Bool { !confirmation.isEmpty && password != confirmation }
    private var canSubmit: Bool {
        password.count >= minimumLength && password == confirmation && !isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text("Choose a password")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("You are signed in as \(session.user?.name ?? "your account"). Pick something only you know.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SecureField("New password", text: $password)
                .textFieldStyle(FieldTextFieldStyle())
                .textContentType(.newPassword)

            SecureField("Type it again", text: $confirmation)
                .textFieldStyle(FieldTextFieldStyle())
                .textContentType(.newPassword)

            Group {
                if tooShort {
                    Text("At least \(minimumLength) characters.")
                } else if mismatch {
                    Text("Those two do not match.")
                } else if let message = session.errorMessage {
                    Text(message)
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(Color.ftStatus(.rework))
            .fixedSize(horizontal: false, vertical: true)

            Button {
                Task {
                    isWorking = true
                    _ = await session.changePassword(to: password)
                    isWorking = false
                }
            } label: {
                if isWorking { ProgressView().tint(.white) } else { Text("Save and continue") }
            }
            .buttonStyle(FieldButtonStyle(isEnabled: canSubmit))
            .disabled(!canSubmit)

            Button("Sign out") { Task { await session.signOut() } }
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, FT.gutter)
        // A sign-in form stretched the width of a tablet is unreadable.
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
