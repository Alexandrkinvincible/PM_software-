//
//  PM Controller
//  Copyright © 2026 Apex Plumbing and Mechanical Services SC. All rights reserved.
//
//  Proprietary and confidential. See LICENSE at the repository root.
//

import SwiftUI
import UniformTypeIdentifiers

// =====================================================================
// The board.
//
// Columns are grouped under the six locked core statuses. That grouping
// is not decoration: it is the one structural fact the whole data model
// rests on, and a Super reading the board should be able to see it
// without being told.
// =====================================================================

/// What a drag carries. Only the id — the ticket itself is already in
/// the store, and shipping a whole model through the drag session would
/// let a stale copy land somewhere.
struct TicketRef: Codable, Transferable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .pmControllerTicket)
    }
}

extension UTType {
    static let pmControllerTicket = UTType(exportedAs: "com.apexmech.pmcontroller.ticket")
}

struct BoardView: View {
    @Environment(Session.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

    let project: Project
    @State private var store: BoardStore
    @State private var openTicket: Ticket?
    @State private var showingNew = false
    @State private var movingTicket: Ticket?

    @MainActor
    init(project: Project, store: BoardStore? = nil) {
        self.project = project
        _store = State(initialValue: store ?? BoardStore(projectId: project.id))
    }

    private var role: ProjectRole { session.role(on: project.id) ?? .lead }
    private var me: UUID { session.user?.id ?? UUID() }
    private var isTablet: Bool { sizeClass == .regular }

    var body: some View {
        Group {
            if store.isLoading && store.tickets.isEmpty {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                board
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if role.canAssign {
                    Button {
                        showingNew = true
                    } label: {
                        Label("New ticket", systemImage: "plus")
                    }
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Text(role.label)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Color.ftAccent.opacity(0.16)))
                    .foregroundStyle(Color.ftAccent)
                    .accessibilityLabel("Your role on this job: \(role.label)")
            }
        }
        .sheet(item: $openTicket) { ticket in
            TicketDetailView(ticket: ticket, store: store, role: role, me: me)
        }
        .sheet(isPresented: $showingNew) {
            NewTicketView(store: store, createdBy: me)
        }
        // The phone has no drag. A card on a ladder is moved by tapping.
        .sheet(item: $movingTicket) { ticket in
            MoveTicketSheet(ticket: ticket, store: store, role: role, me: me)
        }
        .alert("That move was refused",
               isPresented: Binding(get: { store.errorMessage != nil },
                                    set: { if !$0 { store.clearError() } })) {
            Button("OK") { store.clearError() }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    private var board: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(store.groups) { group in
                    statusGroup(group)
                }
            }
            .padding(.horizontal, isTablet ? 24 : FT.gutter)
            .padding(.vertical, 16)
        }
    }

    private func statusGroup(_ group: BoardStore.StatusGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color.ftStatus(group.status))
                    .frame(width: 8, height: 8)
                Text(group.status.label.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(Color.ftStatus(group.status))
                if group.status == .accomplished && !role.canSignOff {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.ftMuted)
                        .accessibilityLabel("You cannot sign work off")
                }
            }
            .padding(.leading, 4)

            HStack(alignment: .top, spacing: 12) {
                ForEach(group.columns) { column in
                    ColumnView(
                        column: column,
                        tickets: store.tickets(in: column)
                            + (column.sortOrder == group.columns.first?.sortOrder
                               ? store.unplacedTickets(for: group.status) : []),
                        store: store,
                        role: role,
                        me: me,
                        isTablet: isTablet,
                        onOpen: { openTicket = $0 },
                        onRequestMove: { movingTicket = $0 }
                    )
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.ftStatus(group.status).opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.ftStatus(group.status).opacity(0.18), lineWidth: 1)
        )
    }
}

// =====================================================================

private struct ColumnView: View {
    let column: BoardColumn
    let tickets: [Ticket]
    let store: BoardStore
    let role: ProjectRole
    let me: UUID
    let isTablet: Bool
    let onOpen: (Ticket) -> Void
    let onRequestMove: (Ticket) -> Void

    @State private var isTargeted = false

    private var width: CGFloat { isTablet ? 260 : 230 }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            ForEach(tickets) { ticket in
                TicketCard(ticket: ticket,
                           isMine: ticket.assignedLead == me,
                           isPending: store.pendingMove == ticket.id)
                    .onTapGesture { onOpen(ticket) }
                    .draggable(TicketRef(id: ticket.id)) {
                        TicketCard(ticket: ticket, isMine: ticket.assignedLead == me,
                                   isPending: false)
                            .frame(width: width)
                            .opacity(0.9)
                    }
                    .contextMenu {
                        Button("Open") { onOpen(ticket) }
                        Button("Move…") { onRequestMove(ticket) }
                    }
            }
            if tickets.isEmpty {
                Text("Empty")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .frame(width: width, alignment: .leading)
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(isTargeted ? Color.ftAccent : Color.clear, lineWidth: 2)
        )
        .dropDestination(for: TicketRef.self) { refs, _ in
            guard let ref = refs.first else { return false }
            Task { @MainActor in
                guard let ticket = store.tickets.first(where: { $0.id == ref.id }) else { return }
                await store.move(ticket, to: column, as: role, me: me)
            }
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(column.name)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            if column.blockedFlag, let party = column.blockedReasonType {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.ftStatus(.rework))
                    .accessibilityLabel("Blocked, waiting on \(party.label)")
            }
            Spacer(minLength: 4)
            Text("\(tickets.count)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
    }
}
