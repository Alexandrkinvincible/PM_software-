//
//  PM Controller
//  Copyright © 2026 Apex Plumbing & Mechanical. All rights reserved.
//
//  Proprietary and confidential. See LICENSE at the repository root.
//

import Foundation

// =====================================================================
// These types mirror the Postgres enums in 0001_schema.sql exactly.
//
// They are deliberately NOT a convenience layer. If someone adds a value
// here that the database does not have, the insert is refused by the
// enum — which is the behaviour SPEC principle 1 asks for. The Swift
// side is a reflection of the database, never the other way round.
// =====================================================================

/// The six locked core statuses. Board columns are cosmetic; this is
/// what every report reads.
enum CoreStatus: String, Codable, CaseIterable, Sendable {
    case open
    case assigned
    case inProgress    = "in_progress"
    case rework
    case review
    case accomplished

    var label: String {
        switch self {
        case .open:         return "Open"
        case .assigned:     return "Assigned"
        case .inProgress:   return "In Progress"
        case .rework:       return "Rework"
        case .review:       return "Review"
        case .accomplished: return "Accomplished"
        }
    }
}

enum ProjectRole: String, Codable, CaseIterable, Sendable {
    case manager
    case pm
    case assistantPM     = "assistant_pm"
    case superintendent  = "super"
    case assistantSuper  = "assistant_super"
    case foreman
    case lead

    var label: String {
        switch self {
        case .manager:        return "Manager"
        case .pm:             return "Project Manager"
        case .assistantPM:    return "Assistant PM"
        case .superintendent: return "Superintendent"
        case .assistantSuper: return "Assistant Super"
        case .foreman:        return "Foreman"
        case .lead:           return "Lead"
        }
    }

    // ---------------------------------------------------------------
    // These mirror the RLS helper functions in 0002_rls.sql.
    //
    // They exist to hide buttons a person cannot use, not to enforce
    // anything. Enforcement is in the database — SPEC principle 8. If
    // one of these ever disagrees with a policy, the database wins and
    // the user gets an error instead of a silent no-op, which is the
    // correct failure.
    // ---------------------------------------------------------------

    /// Review to Accomplished. Assistant PM is excluded: it is one of the
    /// two actions that separate Assistant PM from PM.
    var canSignOff: Bool {
        switch self {
        case .manager, .pm, .superintendent, .assistantSuper: return true
        case .assistantPM, .foreman, .lead:                   return false
        }
    }

    /// Change-order approval. Manager and PM only.
    var canApproveChangeOrder: Bool {
        self == .manager || self == .pm
    }

    /// Create and assign tasks, and kick work back to Rework.
    var canAssign: Bool { self != .lead }

    /// Full material visibility: line items, prices, other people's receipts.
    var seesAllMaterial: Bool {
        switch self {
        case .manager, .pm, .assistantPM: return true
        default:                          return false
        }
    }

    /// The material page at all. A Lead has no access, anywhere.
    var seesAnyMaterial: Bool { self != .lead }

    /// Admin: create people and issue credentials.
    var isAdmin: Bool { self == .manager }
}

struct AppUser: Codable, Identifiable, Sendable {
    let id: UUID
    let email: String
    let name: String
    var phone: String?
    let defaultRole: ProjectRole
    let companyId: UUID
    var trade: String?
    let inHouse: Bool
    let isActive: Bool
    var mustChangePassword: Bool

    enum CodingKeys: String, CodingKey {
        case id, email, name, phone, trade
        case defaultRole        = "default_role"
        case companyId          = "company_id"
        case inHouse            = "in_house"
        case isActive           = "is_active"
        case mustChangePassword = "must_change_password"
    }

    // burdened_rate is absent on purpose. The column grant in 0002_rls.sql
    // denies it to anyone below PM, so selecting it would fail outright
    // for a Lead. Cost lives behind the users_costed view instead.
}

struct Project: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let number: String
    var client: String?
    var contractHours: Double?
    var status: String

    enum CodingKeys: String, CodingKey {
        case id, name, number, client, status
        case contractHours = "contract_hours"
    }
}

/// A person's role on one specific project. The same person can be Super
/// on one job and Foreman on another (SPEC section 3), so role is never
/// read from the user record when a project is in play.
struct Membership: Codable, Identifiable, Sendable {
    let id: UUID
    let projectId: UUID
    let role: ProjectRole
    let active: Bool
    let project: Project?

    enum CodingKeys: String, CodingKey {
        case id, role, active
        case projectId = "project_id"
        case project   = "projects"
    }
}
