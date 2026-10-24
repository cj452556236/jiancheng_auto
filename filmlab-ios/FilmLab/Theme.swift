import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// Darkroom palette: warm black walls, engraved aluminium, safelight amber.
enum Theme {
    static let ink = Color(hex: 0x0F0D0C)
    static let deck = Color(hex: 0x181513)
    static let deck2 = Color(hex: 0x221E1A)
    static let line = Color(hex: 0x36302A)
    static let metal = Color(hex: 0xDDD7CC)
    static let muted = Color(hex: 0x988F82)
    static let body = Color(hex: 0xC3BBAF)
    static let amber = Color(hex: 0xF2A63B)
    static let led = Color(hex: 0xFF6A3C)
    static let viewfinder = Color(hex: 0x080706)
}

@MainActor
enum Haptics {
    private static let selection = UISelectionFeedbackGenerator()
    private static let impact = UIImpactFeedbackGenerator(style: .medium)

    static func tick() { selection.selectionChanged() }
    static func thump() { impact.impactOccurred() }
}

struct Chip: View {
    let title: String
    let selected: Bool
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .foregroundStyle(selected ? Theme.amber : Theme.body)
                .background(selected ? Theme.amber.opacity(0.08) : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(selected ? Theme.amber : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

struct Pill: View {
    let title: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(active ? Color(hex: 0x1A1208) : Theme.metal)
                .background(active ? Theme.amber : Theme.deck2, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? Theme.amber : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct PaneLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold).width(.condensed))
            .tracking(2)
            .foregroundStyle(Theme.muted)
    }
}
