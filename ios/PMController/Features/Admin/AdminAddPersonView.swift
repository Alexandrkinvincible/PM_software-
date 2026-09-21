//
//  PM Controller
//  Copyright © 2026 Apex Plumbing and Mechanical Services SC. All rights reserved.
//
//  Proprietary and confidential. See LICENSE at the repository root.
//

import SwiftUI

// =====================================================================
// Manager-only. Adds a person by email, sets their role, puts them on
// jobs, and issues credentials.
//
// This screen holds NO privileged key. Creating an auth user needs the
// service-role key, which bypasses every policy in 0002_rls.sql — so it
// lives in the `admin-create-user` Edge Function, where Supabase injects
// it server-side and the function re-checks that the caller is really a
// Manager. The app only asks; the server decides.
// =====================================================================

struct AdminAddPersonView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var role: ProjectRole = .lead
    @State private var selectedProjects: Set<UUID> = []
    @State private var isWorking = false
    @State private var issued: IssuedCredentials?
    @State private var failure: String?

    struct IssuedCredentials: Identifiable {
        let id = UUID()
        let email: String
        let temporaryPassword: String
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && email.contains("@")
        && !selectedProjects.isEmpty
        && !isWorking
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    TextField("Full name", text: $name)
                        .textContentType(.name)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Phone (optional)", text: $phone)
                        .keyboardType(.phonePad)
                }

                Section("Role") {
                    Picker("Role", selection: $role) {
                        ForEach(ProjectRole.allCases, id: \.self) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(roleExplanation)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(session.memberships) { membership in
                        if let project = membership.project {
                            Button {
                                toggle(project.id)
                            } label: {
                                HStack {
                                    Text(project.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedProjects.contains(project.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.ftAccent)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Jobs")
                } footer: {
                    // SPEC section 3 — the thing people get wrong.
                    Text("Roles are per job. The same person can be Super on one and Foreman on another.")
                }

                if let failure {
                    Section {
                        Text(failure).foregroundStyle(Color.ftStatus(.rework))
                    }
                }
            }
            .navigationTitle("Add person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(!canSubmit)
                }
            }
            .sheet(item: $issued) { credentials in
                CredentialsHandoffView(credentials: credentials) { dismiss() }
            }
        }
    }

    private var roleExplanation: String {
        switch role {
        case .manager:        return "Everything, on every job."
        case .pm:             return "Runs the job. Signs off work and approves change orders."
        case .assistantPM:    return "A PM without final sign-off or change-order approval. Keeps full material visibility."
        case .superintendent: return "Assigns work and signs it off. Sees only their own receipts."
        case .assistantSuper: return "The same as Superintendent."
        case .foreman:        return "Assigns work to Leads. Sees only their own receipts."
        case .lead:           return "Runs a crew. No material page at all."
        }
    }

    private func toggle(_ id: UUID) {
        if selectedProjects.contains(id) { selectedProjects.remove(id) }
        else { selectedProjects.insert(id) }
    }

    private func create() async {
        isWorking = true
        failure = nil
        defer { isWorking = false }

        struct Request: Encodable {
            let email: String
            let name: String
            let phone: String?
            let role: String
            let projectIds: [UUID]
            enum CodingKeys: String, CodingKey {
                case email, name, phone, role
                case projectIds = "project_ids"
            }
        }
        struct Response: Decodable {
            let email: String
            let temporaryPassword: String
            enum CodingKeys: String, CodingKey {
                case email
                case temporaryPassword = "temporary_password"
            }
        }

        do {
            let response: Response = try await supabase.functions.invoke(
                "admin-create-user",
                options: .init(body: Request(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    name: name.trimmingCharacters(in: .whitespaces),
                    phone: phone.isEmpty ? nil : phone,
                    role: role.rawValue,
                    projectIds: Array(selectedProjects)
                ))
            )
            issued = IssuedCredentials(email: response.email,
                                       temporaryPassword: response.temporaryPassword)
        } catch {
            failure = "Could not create that person. \(error.localizedDescription)"
        }
    }
}

/// The temporary password is shown exactly once and is never stored on
/// the phone. It has to be handed over in person or read out; that is a
/// feature, and it is why must_change_password exists.
private struct CredentialsHandoffView: View {
    let credentials: AdminAddPersonView.IssuedCredentials
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Credentials issued")
                .font(.system(size: 26, weight: .bold, design: .rounded))

            Text("Give these to them now. This password is shown once and is not stored anywhere you can read it again.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                labelled("Email", credentials.email)
                Divider()
                labelled("Temporary password", credentials.temporaryPassword)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: FT.radius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )

            Text("They will be asked to change it the first time they sign in.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Done") {
                dismiss()
                onDone()
            }
            .buttonStyle(FieldButtonStyle())
        }
        .padding(FT.gutter)
        .presentationDetents([.medium])
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 19, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
