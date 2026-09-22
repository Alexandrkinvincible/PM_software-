//
//  PM Controller
//  Copyright © 2026 Apex Plumbing and Mechanical Services SC. All rights reserved.
//
//  Proprietary and confidential. See LICENSE at the repository root.
//

import SwiftUI

/// Moving a card without dragging it.
///
/// This is the phone's only path, and on a tablet it is the one that
/// works with gloves on. It also does something dragging cannot: it
/// shows the moves that are closed to you, and says why. A Lead learns
/// the rule once instead of discovering it as a failed drag.
struct MoveTicketSheet: View {
    let ticket: Ticket
    let store: BoardStore
    let role: ProjectRole
    let me: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ticket.title).font(.system(size: 16, weight: .semibold))
                        Text("\(ticket.area) · \(ticket.system)")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                ForEach(store.groups) { group in
                    Section {
                        ForEach(group.columns) { column in
                            destination(column)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Circle().fill(Color.ftStatus(group.status)).frame(width: 7, height: 7)
                            Text(group.status.label)
                        }
                    }
                }
            }
            .navigationTitle("Move ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .disabled(working)
        }
    }

    @ViewBuilder
    private func destination(_ column: BoardColumn) -> some View {
        let verdict = store.verdict(moving: ticket, to: column, as: role, me: me)
        let isHere = column.id == ticket.boardColumnId

        switch verdict {
        case .allowed where !isHere:
            Button {
                working = true
                Task {
                    let ok = await store.move(ticket, to: column, as: role, me: me)
                    working = false
                    if ok { dismiss() }
                }
            } label: {
                HStack {
                    Text(column.name).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ftAccent)
                }
            }

        case .allowed:
            HStack {
                Text(column.name).foregroundStyle(.secondary)
                Spacer()
                Text("here").font(.system(size: 12)).foregroundStyle(.tertiary)
            }

        case .refused(let why):
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(column.name).foregroundStyle(.tertiary)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Text(why)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(column.name), unavailable. \(why)")
        }
    }
}
