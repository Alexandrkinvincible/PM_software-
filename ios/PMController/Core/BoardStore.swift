//
//  PM Controller
//  Copyright © 2026 Apex Plumbing and Mechanical Services SC. All rights reserved.
//
//  Proprietary and confidential. See LICENSE at the repository root.
//

import Foundation
import Supabase

// =====================================================================
// The board's data, and the one place that decides what a move means.
//
// The rule the whole screen rests on: a move names a COLUMN, and the
// core status is derived from that column — never the reverse. The
// database enforces the same thing from the other side (the
// enforce_column_status_match trigger refuses a mismatch), so the two
// cannot drift apart. That is why status and board_column_id are always
// written in the same update.
// =====================================================================

@MainActor
@Observable
final class BoardStore {

    private(set) var columns: [BoardColumn] = []
    private(set) var tickets: [Ticket] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// Set while a drag is in flight so the card can be drawn in place at
    /// its destination before the server has agreed.
    private(set) var pendingMove: UUID?

    private let projectId: UUID
    private let isPreview: Bool

    init(projectId: UUID, isPreview: Bool = false) {
        self.projectId = projectId
        self.isPreview = isPreview
    }

    // -----------------------------------------------------------------
    // Reading
    // -----------------------------------------------------------------

    func load() async {
        guard !isPreview else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            columns = try await supabase
                .from("board_columns")
                .select("id,project_id,name,sort_order,core_status,blocked_flag,blocked_reason_type,is_system")
                .eq("project_id", value: projectId)
                .order("sort_order")
                .execute()
                .value

            tickets = try await supabase
                .from("tasks")
                .select("""
                    id,project_id,area,system,title,description,est_hours,est_qty,unit,\
                    qty_installed,status,board_column_id,created_by,assigned_foreman,\
                    assigned_lead,rework_count,cost_class,work_class,accomplished_at
                    """)
                .eq("project_id", value: projectId)
                .execute()
                .value
        } catch {
            errorMessage = "Could not load the board. \(error.localizedDescription)"
        }
    }

    func events(for ticket: Ticket) async -> [TicketEvent] {
        guard !isPreview else { return PreviewData.events(for: ticket) }
        do {
            return try await supabase
                .from("task_events")
                .select("id,task_id,from_status,to_status,actor_id,note,created_at")
                .eq("task_id", value: ticket.id)
                .order("created_at")
                .execute()
                .value
        } catch {
            return []
        }
    }

    // -----------------------------------------------------------------
    // Grouping
    //
    // Ten flat columns on a tablet is a scroll with no landmarks. They
    // are grouped under the six core statuses instead, which also makes
    // the locked structure visible — the thing the whole model rests on.
    // -----------------------------------------------------------------

    struct StatusGroup: Identifiable {
        let status: CoreStatus
        let columns: [BoardColumn]
        var id: CoreStatus { status }
    }

    var groups: [StatusGroup] {
        CoreStatus.allCases.compactMap { status in
            let inStatus = columns
                .filter { $0.coreStatus == status }
                .sorted { $0.sortOrder < $1.sortOrder }
            return inStatus.isEmpty ? nil : StatusGroup(status: status, columns: inStatus)
        }
    }

    func tickets(in column: BoardColumn) -> [Ticket] {
        tickets
            .filter { $0.boardColumnId == column.id }
            .sorted { $0.title < $1.title }
    }

    /// Tickets whose board_column_id is not set yet — newly created work,
    /// which the database allows (the column is nullable). They are shown
    /// in the first column of their core status so nothing goes missing.
    func unplacedTickets(for status: CoreStatus) -> [Ticket] {
        tickets
            .filter { $0.boardColumnId == nil && $0.status == status }
            .sorted { $0.title < $1.title }
    }

    // -----------------------------------------------------------------
    // Moving
    // -----------------------------------------------------------------

    /// What a move would mean, without performing it.
    enum MoveVerdict: Equatable {
        case allowed(crossesStatus: Bool)
        case refused(String)
    }

    /// Whether `role` may move `ticket` into `column`, and whether doing so
    /// crosses a core-status boundary.
    ///
    /// This mirrors the policies in 0002_rls.sql. It exists to hide moves
    /// a person cannot make, not to enforce anything — the database is the
    /// enforcement, and if the two ever disagree the database wins and the
    /// person sees an error rather than a silent no-op.
    func verdict(moving ticket: Ticket,
                 to column: BoardColumn,
                 as role: ProjectRole,
                 me: UUID) -> MoveVerdict {

        if column.id == ticket.boardColumnId {
            return .allowed(crossesStatus: false)
        }

        let target = column.coreStatus
        let crosses = target != ticket.status

        // SPEC principle 6. The route back from Accomplished is a new
        // discovered-defect ticket, not a drag.
        if ticket.status == .accomplished {
            return .refused("An Accomplished ticket cannot be reopened. Raise a discovered-defect ticket instead.")
        }

        if !crosses {
            // Inside one core status the board is free — for anyone who
            // can touch the ticket at all.
            if role == .lead && ticket.assignedLead != me {
                return .refused("That ticket is not assigned to you.")
            }
            return .allowed(crossesStatus: false)
        }

        if target == .accomplished && !role.canSignOff {
            return .refused("Only a Manager, PM, Super or Assistant Super can sign work off.")
        }

        if role == .lead {
            guard ticket.assignedLead == me else {
                return .refused("That ticket is not assigned to you.")
            }
            // SPEC section 4 gives the Lead exactly these.
            guard [.assigned, .inProgress, .review].contains(target) else {
                return .refused("A Lead can move work to In Progress or Review only.")
            }
            return .allowed(crossesStatus: true)
        }

        guard role.canAssign else {
            return .refused("Your role cannot move work on this job.")
        }

        return .allowed(crossesStatus: true)
    }

    /// Perform the move. Optimistic: the card lands immediately, because a
    /// board that pauses on every drag feels broken on site Wi-Fi. A
    /// refusal snaps it back and says why.
    @discardableResult
    func move(_ ticket: Ticket,
              to column: BoardColumn,
              as role: ProjectRole,
              me: UUID) async -> Bool {

        switch verdict(moving: ticket, to: column, as: role, me: me) {
        case .refused(let why):
            errorMessage = why
            return false
        case .allowed:
            break
        }

        guard let index = tickets.firstIndex(where: { $0.id == ticket.id }) else { return false }
        let previous = tickets[index]

        tickets[index].boardColumnId = column.id
        tickets[index].status = column.coreStatus
        pendingMove = ticket.id
        errorMessage = nil
        defer { pendingMove = nil }

        if isPreview { return true }

        struct MovePayload: Encodable {
            let status: String
            let boardColumnId: UUID
            let accomplishedAt: Date?
            let accomplishedBy: UUID?
            enum CodingKeys: String, CodingKey {
                case status
                case boardColumnId  = "board_column_id"
                case accomplishedAt = "accomplished_at"
                case accomplishedBy = "accomplished_by"
            }
        }

        // The accomplished_stamped constraint requires who and when to
        // arrive with the status, and to be absent otherwise. Sending
        // them in the same statement is what satisfies it.
        let signingOff = column.coreStatus == .accomplished
        let payload = MovePayload(
            status: column.coreStatus.rawValue,
            boardColumnId: column.id,
            accomplishedAt: signingOff ? Date() : nil,
            accomplishedBy: signingOff ? me : nil
        )

        do {
            try await supabase
                .from("tasks")
                .update(payload)
                .eq("id", value: ticket.id)
                .execute()
            return true
        } catch {
            // The database refused it. Believe the database.
            tickets[index] = previous
            errorMessage = "That move was refused. \(error.localizedDescription)"
            return false
        }
    }

    // -----------------------------------------------------------------
    // Creating
    // -----------------------------------------------------------------

    func create(title: String,
                area: String,
                system: String,
                estHours: Double?,
                estQty: Double?,
                unit: QtyUnit?,
                createdBy: UUID) async -> Bool {

        struct NewTicket: Encodable {
            let projectId: UUID
            let area: String
            let system: String
            let title: String
            let estHours: Double?
            let estQty: Double?
            let unit: String?
            let createdBy: UUID
            let status: String
            enum CodingKeys: String, CodingKey {
                case area, system, title, unit, status
                case projectId = "project_id"
                case estHours  = "est_hours"
                case estQty    = "est_qty"
                case createdBy = "created_by"
            }
        }

        errorMessage = nil
        if isPreview { return true }

        do {
            try await supabase
                .from("tasks")
                .insert(NewTicket(
                    projectId: projectId,
                    area: area.trimmingCharacters(in: .whitespaces),
                    system: system.trimmingCharacters(in: .whitespaces),
                    title: title.trimmingCharacters(in: .whitespaces),
                    estHours: estHours,
                    estQty: estQty,
                    unit: unit?.rawValue,
                    createdBy: createdBy,
                    status: CoreStatus.open.rawValue
                ))
                .execute()
            await load()
            return true
        } catch {
            errorMessage = "Could not create that ticket. \(error.localizedDescription)"
            return false
        }
    }

    func clearError() { errorMessage = nil }

    // -----------------------------------------------------------------
    // Preview
    // -----------------------------------------------------------------

    static func preview(role: ProjectRole = .superintendent) -> BoardStore {
        let store = BoardStore(projectId: PreviewData.welcomeBuilding.id, isPreview: true)
        store.columns = PreviewData.columns
        store.tickets = PreviewData.tickets
        return store
    }
}
