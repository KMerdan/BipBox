// Theme.swift — Bipbox design tokens (port of assets/bipbox.css).
// Semantic colors adapt to light/dark; spacing/radii/type are constants.
import SwiftUI

extension Color {
    /// A color that resolves differently in light vs dark appearance.
    init(_ light: Color, _ dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}

enum BB {
    // accent (overridable by a Tweak later)
    static let accent = Color(hex: 0x0A84FF)
    static let accentPress = Color(hex: 0x0060DF)

    // surfaces
    static let sidebar   = Color(Color(hex: 0xF1F1F4), Color(hex: 0x282829))
    static let content   = Color(Color(hex: 0xFFFFFF), Color(hex: 0x1E1E20))
    static let panel     = Color(Color(hex: 0xFAFAFB), Color(hex: 0x252528))
    static let field     = Color(Color(hex: 0xFFFFFF), Color(hex: 0x1A1A1C))
    static let nodeBg    = Color(Color(hex: 0xFFFFFF), Color(hex: 0x2B2B2F))

    // ink
    static let ink   = Color(Color(hex: 0x1D1D1F), Color(hex: 0xF4F4F6))
    static let ink2  = Color(Color(hex: 0x6E6E73), Color(hex: 0x9B9BA1))
    static let ink3  = Color(Color(hex: 0x98989E), Color(hex: 0x6F6F76))

    // lines / fills
    static let hair       = Color(Color.black.opacity(0.08), Color.white.opacity(0.09))
    static let hairStrong = Color(Color.black.opacity(0.13), Color.white.opacity(0.14))
    static let rowHover   = Color(Color.black.opacity(0.045), Color.white.opacity(0.06))
    static let selFill    = Color(BB.accent.opacity(0.12), BB.accent.opacity(0.26))
    static let chipBg     = Color(Color.black.opacity(0.05), Color.white.opacity(0.09))
    static let edge       = Color(Color.black.opacity(0.16), Color.white.opacity(0.18))

    // status
    static let good  = Color(hex: 0x1F9D57)
    static let warn  = Color(hex: 0xD98B1F)
    static let bad   = Color(hex: 0xE0533D)
    static let info  = Color(hex: 0x0A84FF)
    static let grape = Color(hex: 0x8A5CF6)

    // spacing
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16
    static let s5: CGFloat = 20, s6: CGFloat = 24, s7: CGFloat = 32

    // radius
    static let rRow: CGFloat = 7, rCard: CGFloat = 10, rPanel: CGFloat = 12

    // type
    static func title(_ s: CGFloat = 21) -> Font { .system(size: s, weight: .bold) }
    static func head(_ s: CGFloat = 16) -> Font { .system(size: s, weight: .semibold) }
    static let body = Font.system(size: 14, weight: .medium)
    static let caption = Font.system(size: 12)
    static let mono = Font.system(size: 11.5, design: .monospaced)
    static let groupHead = Font.system(size: 11, weight: .semibold)
}

/// Status pill used across rows and the inspector.
struct StatusPill: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }
}

/// A soft source/relationship chip with a colored dot.
struct DotChip: View {
    let text: String
    let dot: Color
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8).frame(height: 20)
        .background(BB.chipBg, in: Capsule())
        .foregroundStyle(BB.ink2)
    }
}
