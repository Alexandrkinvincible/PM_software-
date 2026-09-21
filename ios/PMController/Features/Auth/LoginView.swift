import SwiftUI

struct LoginView: View {
    @Environment(Session.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && !isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text("PM Controller")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Sign in with the email your manager set up.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }

            TextField("Email", text: $email)
                .textFieldStyle(FieldTextFieldStyle())
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
                .submitLabel(.next)
                .onSubmit { focus = .password }

            SecureField("Password", text: $password)
                .textFieldStyle(FieldTextFieldStyle())
                .textContentType(.password)
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit { Task { await submit() } }

            if let message = session.errorMessage {
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ftStatus(.rework))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isStaticText)
            }

            Button {
                Task { await submit() }
            } label: {
                if isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text("Sign in")
                }
            }
            .buttonStyle(FieldButtonStyle(isEnabled: canSubmit))
            .disabled(!canSubmit)

            // SPEC section 3: no self-registration, anywhere. Saying so
            // here saves a phone call from every new hire.
            Text("Accounts are created by your manager. There is no sign-up.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, FT.gutter)
        // A sign-in form stretched the width of a tablet is unreadable.
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear { focus = .email }
    }

    private func submit() async {
        guard canSubmit else { return }
        isWorking = true
        await session.signIn(email: email, password: password)
        isWorking = false
    }
}
