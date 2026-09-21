//
//  PM Controller
//  Copyright © 2026 Apex Plumbing & Mechanical. All rights reserved.
//
//  Proprietary and confidential. See LICENSE at the repository root.
//

import Foundation
import Supabase

// =====================================================================
// Who is signed in, what they may do, and on which jobs.
//
// The forced password change is a state of this object rather than a
// screen someone can dismiss: SPEC section 3 says there is no
// self-registration and the issued password must be changed at first
// login. Until must_change_password is false, the app has exactly one
// screen.
// =====================================================================

@MainActor
@Observable
final class Session {

    enum State: Equatable {
        case loading
        /// No Supabase project has been configured for this build.
        case unconfigured
        case signedOut
        case mustChangePassword
        case ready
    }

    private(set) var state: State = .loading
    private(set) var user: AppUser?
    private(set) var memberships: [Membership] = []
    private(set) var errorMessage: String?

    /// The role to show in the UI when no single project is selected.
    /// A Manager is company-wide; everyone else is described by the job
    /// they are actually on.
    var headlineRole: ProjectRole? {
        if memberships.contains(where: { $0.role == .manager }) { return .manager }
        return memberships.first?.role ?? user?.defaultRole
    }

    func role(on projectId: UUID) -> ProjectRole? {
        if memberships.contains(where: { $0.role == .manager }) { return .manager }
        return memberships.first { $0.projectId == projectId }?.role
    }

    // -----------------------------------------------------------------
    // Preview
    // -----------------------------------------------------------------

    /// A session that never touches the network, backed by PreviewData.
    /// Used by SwiftUI previews and by the -PMControllerPreview launch
    /// argument, which is how CI drives the app in a Simulator.
    static func preview(
        user: AppUser = PreviewData.superintendent,
        memberships: [Membership] = PreviewData.superintendentMemberships,
        state: State = .ready
    ) -> Session {
        let session = Session()
        session.user = user
        session.memberships = memberships
        session.state = state
        session.isPreview = true
        return session
    }

    /// Named personas, so CI can photograph the app as each role.
    /// The names match the ones in supabase/seed.sql.
    static func preview(persona: String) -> Session {
        switch persona {
        case "lead":
            return .preview(user: PreviewData.lead,
                            memberships: PreviewData.leadMemberships)
        case "manager":
            return .preview(user: PreviewData.manager,
                            memberships: PreviewData.managerMemberships)
        case "first-login":
            return .preview(user: PreviewData.lead,
                            memberships: PreviewData.leadMemberships,
                            state: .mustChangePassword)
        case "signed-out":
            return .preview(state: .signedOut)
        default:
            return .preview()
        }
    }

    private(set) var isPreview = false

    // -----------------------------------------------------------------
    // Lifecycle
    // -----------------------------------------------------------------

    func start() async {
        // A preview session is already populated and has nowhere to call.
        guard !isPreview else { return }

        // An unconfigured build has no project to reach. RootView shows
        // the setup instructions rather than a login form that can only
        // ever fail.
        guard AppConfig.isConfigured else {
            state = .unconfigured
            return
        }

        for await change in supabase.auth.authStateChanges {
            switch change.event {
            case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                if let signedIn = change.session {
                    await loadProfile(userId: signedIn.user.id)
                } else {
                    state = .signedOut
                }
            case .signedOut:
                user = nil
                memberships = []
                state = .signedOut
            default:
                break
            }
        }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        do {
            _ = try await supabase.auth.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            // loadProfile runs from the authStateChanges stream.
        } catch {
            // Deliberately vague: distinguishing "no such user" from "wrong
            // password" tells an attacker which emails are real.
            errorMessage = "That email and password did not match."
        }
    }

    func signOut() async {
        try? await supabase.auth.signOut()
    }

    // -----------------------------------------------------------------
    // Profile
    // -----------------------------------------------------------------

    /// `userId` comes from the auth stream on sign-in. A refresh from the
    /// UI has nobody to hand it one, so it falls back to whoever is
    /// already loaded.
    func loadProfile(userId: UUID? = nil) async {
        guard let uid = userId ?? user?.id else {
            state = .signedOut
            return
        }
        do {
            let me: AppUser = try await supabase
                .from("users")
                .select("id,email,name,phone,default_role,company_id,trade,in_house,is_active,must_change_password")
                .eq("id", value: uid)
                .single()
                .execute()
                .value

            // Deactivation is the only way a person leaves (SPEC principle
            // 9), so an inactive account must be turned away at the door —
            // the row still exists and would otherwise sign in fine.
            guard me.isActive else {
                errorMessage = "This account is no longer active. Speak to your manager."
                try? await supabase.auth.signOut()
                return
            }

            user = me

            // One round trip: memberships with their project embedded.
            memberships = try await supabase
                .from("project_members")
                .select("id,project_id,role,active,projects(id,name,number,client,contract_hours,status)")
                .eq("user_id", value: uid)
                .eq("active", value: true)
                .execute()
                .value

            state = me.mustChangePassword ? .mustChangePassword : .ready
        } catch {
            errorMessage = "Could not load your profile. \(error.localizedDescription)"
            state = .signedOut
        }
    }

    // -----------------------------------------------------------------
    // First-login password change
    // -----------------------------------------------------------------

    func changePassword(to newPassword: String) async -> Bool {
        errorMessage = nil
        guard let uid = user?.id else { return false }
        do {
            try await supabase.auth.update(user: UserAttributes(password: newPassword))

            // The guard trigger in 0002_rls.sql permits exactly this write:
            // the person themselves, true -> false, and nothing else on the
            // row. An admin is not required, and no other column moves.
            try await supabase
                .from("users")
                .update(["must_change_password": false])
                .eq("id", value: uid)
                .execute()

            await loadProfile()
            return true
        } catch {
            errorMessage = "Could not change the password. \(error.localizedDescription)"
            return false
        }
    }
}
