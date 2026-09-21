//
//  PM Controller
//  Copyright © 2026 Apex Plumbing & Mechanical. All rights reserved.
//
//  Proprietary and confidential. See LICENSE at the repository root.
//

import SwiftUI

// =====================================================================
// Built for a phone held in one hand, in daylight, by someone wearing
// gloves. Every number here comes from that.
// =====================================================================

extension Color {
    /// Deep slate rather than pure black: pure black on OLED smears when
    /// the phone moves, and this screen is read while walking.
    static let ftInk        = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let ftPaper      = Color(red: 0.98, green: 0.98, blue: 0.97)
    static let ftAccent     = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let ftMuted      = Color(red: 0.42, green: 0.44, blue: 0.47)
    static let ftLine       = Color(red: 0.87, green: 0.87, blue: 0.86)

    /// Status colours. Rework is the only alarming one on purpose — it is
    /// the only status that means someone has to go back.
    static func ftStatus(_ status: CoreStatus) -> Color {
        switch status {
        case .open:         return Color(red: 0.45, green: 0.47, blue: 0.51)
        case .assigned:     return Color(red: 0.24, green: 0.44, blue: 0.72)
        case .inProgress:   return Color(red: 0.16, green: 0.53, blue: 0.44)
        case .rework:       return Color(red: 0.76, green: 0.29, blue: 0.24)
        case .review:       return Color(red: 0.72, green: 0.52, blue: 0.13)
        case .accomplished: return Color(red: 0.25, green: 0.50, blue: 0.29)
        }
    }
}

enum FT {
    /// Apple's minimum is 44. Gloves are not Apple's minimum.
    static let tapTarget: CGFloat = 56
    static let gutter: CGFloat    = 20
    static let radius: CGFloat    = 14
}

/// The one button style in the app. A single shape, so a Lead learns it
/// once and never has to read a screen again.
struct FieldButtonStyle: ButtonStyle {
    var tone: Color = .ftAccent
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: FT.tapTarget)
            .background(
                RoundedRectangle(cornerRadius: FT.radius, style: .continuous)
                    .fill(isEnabled ? tone : Color.ftMuted.opacity(0.45))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct FieldTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 18))
            .padding(.horizontal, 16)
            .frame(minHeight: FT.tapTarget)
            .background(
                RoundedRectangle(cornerRadius: FT.radius, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: FT.radius, style: .continuous)
                    .stroke(Color.ftLine, lineWidth: 1)
            )
    }
}

struct StatusChip: View {
    let status: CoreStatus
    var body: some View {
        Text(status.label.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.ftStatus(status)))
            .accessibilityLabel("Status: \(status.label)")
    }
}
