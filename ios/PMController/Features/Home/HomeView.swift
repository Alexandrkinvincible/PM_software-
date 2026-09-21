//
//  PM Controller
//  Copyright © 2026 Apex Plumbing & Mechanical. All rights reserved.
//
//  Proprietary and confidential. See LICENSE at the repository root.
//

import SwiftUI

/// Phase 1's home screen, and nothing more: who you are, what you may do,
/// and which jobs you are on. The board, time capture, material and the
/// progress page are Phases 2 through 7 and are not stubbed here — a stub
/// a Lead can tap is a support call.
struct HomeView: View {
    @Environment(Session.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showingAdmin = false

    private var role: ProjectRole? { session.headlineRole }

    /// A tablet in landscape is nearly a thousand points wide. One column
    /// of text across that is unreadable, and stretched cards look like a
    /// phone app someone forgot to finish.
    private var isWide: Bool { sizeClass == .regular }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if isWide {
                        VStack(alignment: .leading, spacing: 28) {
                            identity
                            HStack(alignment: .top, spacing: 28) {
                                jobs
                                permissions
                                    .frame(width: 380)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 24) {
                            identity
                            jobs
                            permissions
                        }
                    }
                }
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, isWide ? 32 : FT.gutter)
                .padding(.vertical, isWide ? 24 : 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("PM Controller")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if role?.isAdmin == true {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add person") { showingAdmin = true }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign out") { Task { await session.signOut() } }
                }
            }
            .sheet(isPresented: $showingAdmin) { AdminAddPersonView() }
            .refreshable { await session.loadProfile() }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.user?.name ?? "—")
                .font(.system(size: isWide ? 36 : 28, weight: .bold, design: .rounded))
            if let role {
                Text(role.label)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.ftAccent)
            }
            Text(session.user?.email ?? "")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            if session.user?.inHouse == false {
                Text("Contractor")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.ftMuted.opacity(0.22)))
                    .padding(.top, 2)
            }
        }
    }

    private var jobs: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your jobs")
                .font(.system(size: 13, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            if session.memberships.isEmpty {
                Text("You are not on a job yet. Your manager assigns these.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(session.memberships) { membership in
                    if let project = membership.project {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(project.name)
                                    .font(.system(size: 17, weight: .semibold))
                                Text("#\(project.number)\(project.client.map { " · \($0)" } ?? "")")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            // The role that matters is the one on THIS job.
                            Text(membership.role.label)
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(Capsule().fill(Color.ftAccent.opacity(0.16)))
                                .foregroundStyle(Color.ftAccent)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: FT.radius, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                    }
                }
            }
        }
    }

    /// Shown because Phase 1's whole point is that the role matrix is real.
    /// Every line here is answered by a policy in 0002_rls.sql, not by this
    /// screen.
    private var permissions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What you can do")
                .font(.system(size: 13, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                row("Create and assign tasks",   role?.canAssign ?? false)
                Divider()
                row("Kick work back to Rework",  role?.canAssign ?? false)
                Divider()
                row("Sign off Accomplished",     role?.canSignOff ?? false)
                Divider()
                row("Approve change orders",     role?.canApproveChangeOrder ?? false)
                Divider()
                row("Material page",             role?.seesAnyMaterial ?? false,
                    note: (role?.seesAnyMaterial ?? false)
                          ? ((role?.seesAllMaterial ?? false) ? "Everything" : "Your own uploads")
                          : nil)
                Divider()
                row("Add people",                role?.isAdmin ?? false)
            }
            .background(
                RoundedRectangle(cornerRadius: FT.radius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private func row(_ label: String, _ allowed: Bool, note: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(allowed ? Color.ftStatus(.accomplished) : Color.ftMuted)
                .font(.system(size: 19))
            Text(label).font(.system(size: 16))
            Spacer(minLength: 8)
            if let note {
                Text(note).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(allowed ? "allowed" : "not allowed")\(note.map { ", \($0)" } ?? "")")
    }
}
