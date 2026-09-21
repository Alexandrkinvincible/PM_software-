//
//  PM Controller
//  Copyright © 2026 Apex Plumbing and Mechanical Services SC. All rights reserved.
//
//  Proprietary and confidential. See LICENSE at the repository root.
//

import SwiftUI

/// Create a ticket. Area and system are free text for now — SPEC's own
/// open question is whether they should be a fixed list per project, and
/// that needs PCM's estimate breakdown to answer. Flagged rather than
/// guessed at.
struct NewTicketView: View {
    let store: BoardStore
    let createdBy: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var area = ""
    @State private var system = ""
    @State private var hours = ""
    @State private var quantity = ""
    @State private var unit: QtyUnit = .ft
    @State private var working = false

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
        && !area.trimmingCharacters(in: .whitespaces).isEmpty
        && !system.trimmingCharacters(in: .whitespaces).isEmpty
        && !working
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("The work") {
                    TextField("Title", text: $title)
                    TextField("Area — e.g. Welcome Bldg, Area A", text: $area)
                    TextField("System — e.g. domestic water, gas", text: $system)
                }

                Section {
                    TextField("Estimated hours", text: $hours)
                        .keyboardType(.decimalPad)
                    HStack {
                        TextField("Estimated quantity", text: $quantity)
                            .keyboardType(.decimalPad)
                        Picker("", selection: $unit) {
                            ForEach(QtyUnit.allCases, id: \.self) { u in
                                Text(u.rawValue).tag(u)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 110)
                    }
                } header: {
                    Text("Estimate")
                } footer: {
                    Text("A quantity needs a unit — the database refuses one without the other, so a close-out can never read \"340\" of nothing.")
                }
            }
            .navigationTitle("New ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        working = true
                        Task {
                            let ok = await store.create(
                                title: title, area: area, system: system,
                                estHours: Double(hours),
                                estQty: Double(quantity),
                                unit: Double(quantity) == nil ? nil : unit,
                                createdBy: createdBy
                            )
                            working = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }
}
