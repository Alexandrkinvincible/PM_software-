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
}
