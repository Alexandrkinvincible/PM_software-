//
//  PM Controller
//  Copyright © 2026 Apex Plumbing and Mechanical Services SC. All rights reserved.
//
//  Proprietary and confidential. See LICENSE at the repository root.
//

import Foundation

// =====================================================================
// Canned data for SwiftUI previews, for CI screenshots, and for anyone
// who wants to see the app before there is a Supabase project to point
// it at.
//
// It is deliberately the same shape as supabase/seed.sql — the same
// people, the same two jobs, the same "Foreman here, Super there" case —
// so a screenshot taken from this is a fair picture of the real thing
// rather than a flattering one.
//
// Nothing in the UI can switch this on. It is reachable only via the
// -PMControllerPreview launch argument.
// =====================================================================

enum PreviewData {

    static let houseCompany = UUID(uuidString: "00000000-0000-4000-8000-0000000000c1")!

    static let welcomeBuilding = Project(
        id: UUID(uuidString: "00000000-0000-4000-8000-0000000000f1")!,
        name: "Welcome Building — Phase 2",
        number: "2601",
        client: "Northside Construction Group",
        contractHours: 4200,
        status: "active"
    )

    static let riversideClinic = Project(
        id: UUID(uuidString: "00000000-0000-4000-8000-0000000000f2")!,
        name: "Riverside Clinic",
        number: "2602",
        client: "Northside Construction Group",
        contractHours: 1800,
        status: "active"
    )

    static func user(_ role: ProjectRole, name: String, email: String) -> AppUser {
        AppUser(
            id: UUID(),
            email: email,
            name: name,
            phone: "555-0142",
            defaultRole: role,
            companyId: houseCompany,
            trade: "plumbing",
            inHouse: true,
            isActive: true,
            mustChangePassword: false
        )
    }

    static func membership(_ project: Project, _ role: ProjectRole) -> Membership {
        Membership(id: UUID(), projectId: project.id, role: role, active: true, project: project)
    }

    /// The default preview subject: a Superintendent on one job who is a
    /// Foreman on another. Chosen because it is the case people get wrong
    /// — roles are per project, never per person.
    static let superintendent = user(.superintendent, name: "Tom Brenner", email: "tom@example.com")

    static let superintendentMemberships = [
        membership(welcomeBuilding, .superintendent),
        membership(riversideClinic, .foreman)
    ]

    static let lead = user(.lead, name: "Junior Alvarez", email: "junior@example.com")
    static let leadMemberships = [membership(welcomeBuilding, .lead)]

    static let manager = user(.manager, name: "Dana Whitfield", email: "dana@example.com")
    static let managerMemberships = [
        membership(welcomeBuilding, .manager),
        membership(riversideClinic, .manager)
    ]

    // -----------------------------------------------------------------
    // Board — the same shape as supabase/seed.sql, including the ten
    // columns of the Welcome Building and the custom ones that map onto
    // a locked core status.
    // -----------------------------------------------------------------

    private static func columnId(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-0000000000b%01x", n))!
    }

    static let columns: [BoardColumn] = [
        .init(id: columnId(1), projectId: welcomeBuilding.id, name: "Open",
              sortOrder: 10, coreStatus: .open, blockedFlag: false,
              blockedReasonType: nil, isSystem: true),
        .init(id: columnId(2), projectId: welcomeBuilding.id, name: "Assigned",
              sortOrder: 20, coreStatus: .assigned, blockedFlag: false,
              blockedReasonType: nil, isSystem: true),
        .init(id: columnId(3), projectId: welcomeBuilding.id, name: "In Progress",
              sortOrder: 30, coreStatus: .inProgress, blockedFlag: false,
              blockedReasonType: nil, isSystem: true),
        .init(id: columnId(4), projectId: welcomeBuilding.id, name: "Waiting on GC",
              sortOrder: 40, coreStatus: .inProgress, blockedFlag: true,
              blockedReasonType: .gc, isSystem: false),
        .init(id: columnId(5), projectId: welcomeBuilding.id, name: "Material on order",
              sortOrder: 50, coreStatus: .inProgress, blockedFlag: true,
              blockedReasonType: .material, isSystem: false),
        .init(id: columnId(6), projectId: welcomeBuilding.id, name: "Ready for inspection",
              sortOrder: 60, coreStatus: .review, blockedFlag: false,
              blockedReasonType: nil, isSystem: false),
        .init(id: columnId(7), projectId: welcomeBuilding.id, name: "Review",
              sortOrder: 70, coreStatus: .review, blockedFlag: false,
              blockedReasonType: nil, isSystem: true),
        .init(id: columnId(8), projectId: welcomeBuilding.id, name: "Punch list",
              sortOrder: 80, coreStatus: .rework, blockedFlag: false,
              blockedReasonType: nil, isSystem: false),
        .init(id: columnId(9), projectId: welcomeBuilding.id, name: "Rework",
              sortOrder: 90, coreStatus: .rework, blockedFlag: false,
              blockedReasonType: nil, isSystem: true),
        .init(id: columnId(10), projectId: welcomeBuilding.id, name: "Accomplished",
              sortOrder: 100, coreStatus: .accomplished, blockedFlag: false,
              blockedReasonType: nil, isSystem: true)
    ]

    /// The Lead the preview signs in as owns the two tickets that make the
    /// role rules visible: one he may move, one he may not.
    static let leadId = lead.id
    private static let superId = superintendent.id

    private static func ticketId(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-0000000000a%01x", n))!
    }

    static let tickets: [Ticket] = [
        .init(id: ticketId(1), projectId: welcomeBuilding.id,
              area: "Welcome Bldg", system: "domestic water",
              title: "2nd floor branch rough-in",
              description: "Type L copper, 2in main with 3/4in branches to each core.",
              estHours: 64, estQty: 380, unit: .ft, qtyInstalled: nil,
              status: .assigned, boardColumnId: columnId(2),
              createdBy: superId, assignedForeman: nil, assignedLead: leadId,
              reworkCount: 0, costClass: .base, workClass: .firstTime,
              accomplishedAt: nil),

        .init(id: ticketId(2), projectId: welcomeBuilding.id,
              area: "Area A", system: "sanitary",
              title: "Underground stub-outs",
              description: "24 stubs, dimensions off the architectural, not the plumbing sheet.",
              estHours: 40, estQty: 24, unit: .ea, qtyInstalled: nil,
              status: .open, boardColumnId: columnId(1),
              createdBy: superId, assignedForeman: nil, assignedLead: nil,
              reworkCount: 0, costClass: .base, workClass: .firstTime,
              accomplishedAt: nil),

        .init(id: ticketId(3), projectId: welcomeBuilding.id,
              area: "Area B", system: "gas",
              title: "Rooftop unit gas piping",
              description: nil,
              estHours: 28, estQty: 160, unit: .ft, qtyInstalled: nil,
              status: .inProgress, boardColumnId: columnId(3),
              createdBy: superId, assignedForeman: nil, assignedLead: nil,
              reworkCount: 0, costClass: .base, workClass: .firstTime,
              accomplishedAt: nil),

        .init(id: ticketId(4), projectId: welcomeBuilding.id,
              area: "Area A", system: "domestic water",
              title: "Hanger spacing correction",
              description: "Hangers at 12ft, spec is 8ft.",
              estHours: 12, estQty: 90, unit: .ft, qtyInstalled: nil,
              status: .rework, boardColumnId: columnId(8),
              createdBy: superId, assignedForeman: nil, assignedLead: leadId,
              reworkCount: 1, costClass: .base, workClass: .reviewRework,
              accomplishedAt: nil),

        .init(id: ticketId(5), projectId: welcomeBuilding.id,
              area: "Welcome Bldg", system: "storm",
              title: "Roof drain leaders",
              description: nil,
              estHours: 36, estQty: 210, unit: .ft, qtyInstalled: 210,
              status: .accomplished, boardColumnId: columnId(10),
              createdBy: superId, assignedForeman: nil, assignedLead: nil,
              reworkCount: 0, costClass: .base, workClass: .firstTime,
              accomplishedAt: Date(timeIntervalSinceNow: -86_400 * 6)),

        .init(id: ticketId(6), projectId: welcomeBuilding.id,
              area: "Area B", system: "domestic water",
              title: "Core drilling — waiting on GC layout",
              description: nil,
              estHours: 16, estQty: 8, unit: .ea, qtyInstalled: nil,
              status: .inProgress, boardColumnId: columnId(4),
              createdBy: superId, assignedForeman: nil, assignedLead: nil,
              reworkCount: 0, costClass: .base, workClass: .firstTime,
              accomplishedAt: nil)
    ]

    static func events(for ticket: Ticket) -> [TicketEvent] {
        let base = Date(timeIntervalSinceNow: -86_400 * 9)
        var out: [TicketEvent] = [
            .init(id: UUID(), taskId: ticket.id, fromStatus: nil, toStatus: .open,
                  actorId: superId, note: nil, createdAt: base)
        ]
        if ticket.status != .open {
            out.append(.init(id: UUID(), taskId: ticket.id, fromStatus: .open,
                             toStatus: .assigned, actorId: superId, note: nil,
                             createdAt: base.addingTimeInterval(86_400)))
        }
        if [.inProgress, .review, .rework, .accomplished].contains(ticket.status) {
            out.append(.init(id: UUID(), taskId: ticket.id, fromStatus: .assigned,
                             toStatus: .inProgress, actorId: leadId, note: nil,
                             createdAt: base.addingTimeInterval(86_400 * 2)))
        }
        if ticket.reworkCount > 0 {
            out.append(.init(id: UUID(), taskId: ticket.id, fromStatus: .review,
                             toStatus: .rework, actorId: superId,
                             note: "Hangers at 12ft, spec is 8ft.",
                             createdAt: base.addingTimeInterval(86_400 * 4)))
        }
        if ticket.status == .accomplished {
            out.append(.init(id: UUID(), taskId: ticket.id, fromStatus: .review,
                             toStatus: .accomplished, actorId: superId, note: nil,
                             createdAt: base.addingTimeInterval(86_400 * 5)))
        }
        return out
    }
}
