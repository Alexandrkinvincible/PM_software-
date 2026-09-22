//
//  PM Controller
//  Copyright © 2026 Apex Plumbing and Mechanical Services SC. All rights reserved.
//
//  Proprietary and confidential. See LICENSE at the repository root.
//

import SwiftUI

/// One card. What a Super needs at a glance, and nothing else: what the
/// work is, where it is, who has it, what it was estimated at, and
/// whether it has been kicked back.
struct TicketCard: View {
    let ticket: Ticket
    let isMine: Bool
    let isPending: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ticket.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(ticket.area) · \(ticket.system)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                if let hours = ticket.estHours {
                    tag("\(Int(hours))h")
                }
                if let qty = ticket.estQty, let unit = ticket.unit {
                    tag("\(Int(qty)) \(unit.rawValue)")
                }
                if ticket.reworkCount > 0 {
                    tag("rework ×\(ticket.reworkCount)", tone: Color.ftStatus(.rework))
                }
                if ticket.costClass == .changeOrder {
                    tag("CO", tone: Color.ftStatus(.review))
                }
                Spacer(minLength: 0)
                if isMine {
                    Image(systemName: "person.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.ftAccent)
                        .accessibilityLabel("Assigned to you")
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isMine ? Color.ftAccent.opacity(0.45) : Color.ftLine, lineWidth: 1)
        )
        .opacity(isPending ? 0.55 : 1)
        .animation(.easeOut(duration: 0.15), value: isPending)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(ticket.title), \(ticket.area), \(ticket.system)"
            + (isMine ? ", assigned to you" : "")
            + (ticket.reworkCount > 0 ? ", reworked \(ticket.reworkCount) times" : "")
        )
    }

    private func tag(_ text: String, tone: Color = .ftMuted) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(tone)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(tone.opacity(0.12)))
    }
}
