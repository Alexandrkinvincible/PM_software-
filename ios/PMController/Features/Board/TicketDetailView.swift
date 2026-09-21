//
//  PM Controller
//  Copyright © 2026 Apex Plumbing and Mechanical Services SC. All rights reserved.
//
//  Proprietary and confidential. See LICENSE at the repository root.
//

import SwiftUI

/// A ticket, opened.
///
/// The event history is shown because it is the product (SPEC: "the audit
/// trail is the product"). It is read-only here and read-only in the
/// database — `task_events` has no client write policy at all.
struct TicketDetailView: View {
    let ticket: Ticket
    let store: BoardStore
    let role: ProjectRole
    let me: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var events: [TicketEvent] = []
    @State private var loadingEvents = true

    private var column: BoardColumn? {
        store.columns.first { $0.id == ticket.boardColumnId }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    heading
                    facts
                    history
                }
                .padding(FT.gutter)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            events = await store.events(for: ticket)
            loadingEvents = false
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusChip(status: ticket.status)
                if let column, !column.isSystem {
                    Text(column.name)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
            }
            Text(ticket.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(ticket.area) · \(ticket.system)")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            if let description = ticket.description {
                Text(description)
                    .font(.system(size: 15))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private var facts: some View {
        VStack(spacing: 0) {
            if let hours = ticket.estHours {
                row("Estimated hours", "\(Int(hours))")
                Divider()
            }
            if let qty = ticket.estQty, let unit = ticket.unit {
                row("Estimated quantity", "\(Int(qty)) \(unit.label)")
                Divider()
            }
            if let installed = ticket.qtyInstalled, let unit = ticket.unit {
                row("Installed", "\(Int(installed)) \(unit.label)")
                Divider()
            }
            row("Cost class", ticket.costClass.label)
            Divider()
            row("Work class", ticket.workClass.label)
            if ticket.reworkCount > 0 {
                Divider()
                row("Kicked back", "\(ticket.reworkCount) time\(ticket.reworkCount == 1 ? "" : "s")",
                    tone: Color.ftStatus(.rework))
            }
            if let at = ticket.accomplishedAt {
                Divider()
                row("Signed off", at.formatted(date: .abbreviated, time: .omitted),
                    tone: Color.ftStatus(.accomplished))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: FT.radius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(.system(size: 13, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            if loadingEvents {
                ProgressView().padding(.vertical, 8)
            } else if events.isEmpty {
                Text("No events recorded.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(events) { event in
                        HStack(alignment: .top, spacing: 11) {
                            Circle()
                                .fill(Color.ftStatus(event.toStatus))
                                .frame(width: 9, height: 9)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.fromStatus.map { "\($0.label) → \(event.toStatus.label)" }
                                     ?? "Created as \(event.toStatus.label)")
                                    .font(.system(size: 14, weight: .medium))
                                if let note = event.note {
                                    Text(note)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        if event.id != events.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: FT.radius, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }

            Text("History is never rewritten. A problem found after sign-off becomes a new ticket that links back to this one.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ label: String, _ value: String, tone: Color = .primary) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).font(.system(size: 15, weight: .medium)).foregroundStyle(tone)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
    }
}
