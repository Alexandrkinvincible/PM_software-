//
//  PM Controller
//  Copyright © 2026 Apex Plumbing and Mechanical Services SC. All rights reserved.
//
//  Proprietary and confidential. See LICENSE at the repository root.
//

import Foundation

// =====================================================================
// The board's types.
//
// A note on the name: the work item is a `Ticket`, not a `Task`. Swift
// Concurrency already owns `Task`, and a model type that shadows it makes
// every `Task { }` in the file ambiguous. SPEC calls them tickets in
// several places anyway ("clicking any figure returns its ticket list"),
// so the domain language and the compiler agree for once.
// =====================================================================

/// A column on a project's board. Custom columns are cosmetic; the
/// `coreStatus` underneath is what every report reads (SPEC principle 2).
struct BoardColumn: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let projectId: UUID
    let name: String
    let sortOrder: Int
    let coreStatus: CoreStatus
    let blockedFlag: Bool
    let blockedReasonType: BlockedParty?
    let isSystem: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case projectId          = "project_id"
        case sortOrder          = "sort_order"
        case coreStatus         = "core_status"
        case blockedFlag        = "blocked_flag"
        case blockedReasonType  = "blocked_reason_type"
        case isSystem           = "is_system"
    }
}

enum BlockedParty: String, Codable, CaseIterable, Sendable {
    case gc
    case otherTrade = "other_trade"
    case material
    case owner
    case us

    var label: String {
        switch self {
        case .gc:         return "GC"
        case .otherTrade: return "Another trade"
        case .material:   return "Material"
        case .owner:      return "Owner"
        case .us:         return "Us"
        }
    }
}

enum CostClass: String, Codable, CaseIterable, Sendable {
    case base
    case changeOrder = "change_order"
    case ourCost     = "our_cost"

    var label: String {
        switch self {
        case .base:        return "Base contract"
        case .changeOrder: return "Change order"
        case .ourCost:     return "Our cost"
        }
    }
}

enum WorkClass: String, Codable, CaseIterable, Sendable {
    case firstTime         = "first_time"
    case reviewRework      = "review_rework"
    case discoveredDefect  = "discovered_defect"

    var label: String {
        switch self {
        case .firstTime:        return "First-time work"
        case .reviewRework:     return "Review rework"
        case .discoveredDefect: return "Discovered defect"
        }
    }
}

enum QtyUnit: String, Codable, CaseIterable, Sendable {
    case ft, ea
    var label: String { self == .ft ? "feet" : "each" }
}

/// One piece of work. The fields here are the ones the board and its
/// detail sheet need; the money and schedule columns exist in the
/// database and arrive in Phases 6a and 6b.
struct Ticket: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let projectId: UUID
    var area: String
    var system: String
    var title: String
    var description: String?

    var estHours: Double?
    var estQty: Double?
    var unit: QtyUnit?
    var qtyInstalled: Double?

    var status: CoreStatus
    var boardColumnId: UUID?

    let createdBy: UUID
    var assignedForeman: UUID?
    var assignedLead: UUID?

    var reworkCount: Int
    var costClass: CostClass
    var workClass: WorkClass
    var accomplishedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, area, system, title, description, unit, status
        case projectId       = "project_id"
        case estHours        = "est_hours"
        case estQty          = "est_qty"
        case qtyInstalled    = "qty_installed"
        case boardColumnId   = "board_column_id"
        case createdBy       = "created_by"
        case assignedForeman = "assigned_foreman"
        case assignedLead    = "assigned_lead"
        case reworkCount     = "rework_count"
        case costClass       = "cost_class"
        case workClass       = "work_class"
        case accomplishedAt  = "accomplished_at"
    }
}

/// One row of the audit trail. Append-only in the database; read-only here.
struct TicketEvent: Codable, Identifiable, Sendable {
    let id: UUID
    let taskId: UUID
    let fromStatus: CoreStatus?
    let toStatus: CoreStatus
    let actorId: UUID
    let note: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, note
        case taskId     = "task_id"
        case fromStatus = "from_status"
        case toStatus   = "to_status"
        case actorId    = "actor_id"
        case createdAt  = "created_at"
    }
}
