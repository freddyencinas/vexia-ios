import SwiftUI
import UIKit

/// Vexia design tokens.
/// Every token is light/dark adaptive; dark values keep ≥4.5:1 on #000/#1C1C1E (text) and ≥3:1 for
/// white bold labels on filled controls.
enum VexiaColor {
    /// Accent for text, icons, chart lines and the app tint.
    static let brandBlue = Color(light: 0x15307C, dark: 0x6B8FF2)
    /// Solid brand surface that carries white content (hero cards, selected chips, bubbles).
    static let brandFill = Color(light: 0x15307C, dark: 0x1F3C8F)
    static let brandGreen = Color(light: 0x0C7D59, dark: 0x1F9E70)
    static let success = Color(light: 0x10B981, dark: 0x34D399)
    static let error = Color(light: 0xEF4444, dark: 0xF87171)
    static let warning = Color(light: 0xF59E0B, dark: 0xFBBF24)
    static let info = Color(light: 0x3B82F6, dark: 0x60A5FA)

    static let income = success

    // Text-safe variants (≥4.5:1 on white/#F2F2F7 in light, on #000/#1C1C1E in dark) — design review finding.
    static let textSecondary = Color(light: 0x4B5563, dark: 0x9CA3AF)
    static let incomeText = Color(light: 0x0A7A55, dark: 0x34D399)
    static let expenseText = Color(light: 0xB42318, dark: 0xF87171)
    static let warningText = Color(light: 0x7A2E0E, dark: 0xFCD34D)
    static let cautionText = Color(light: 0xB54708, dark: 0xFDBA74)
    /// Solid red for bars/fills (no text on top).
    static let expenseFill = Color(light: 0xD92D20, dark: 0xE5484D)

    // Soft tinted surfaces (badges, tracks, notices).
    static let tintSoft = Color(light: 0xE8EDFA, dark: 0x1D2A4D)
    static let greenSoft = Color(light: 0xE6F4EE, dark: 0x113228)
    static let amberSoft = Color(light: 0xFEF3E2, dark: 0x3A2A12)
    static let redSoft = Color(light: 0xFDE8E7, dark: 0x3D1A1A)
    static let blueMuted = Color(light: 0xC7D2EE, dark: 0x3A4A70)
    static let violet = Color(light: 0x5B3BB0, dark: 0xA78BFA)
    static let violetSoft = Color(light: 0xEEE8FA, dark: 0x2A2245)

    /// Gradient used by hero cards (balance, AI orb). Dark brand tones read well in both modes.
    static let heroGradient = LinearGradient(
        colors: [Color(hex: 0x15307C), Color(hex: 0x1E4FB8), Color(hex: 0x0C7D59)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Gradient for glyphs/text drawn directly on the page background (adaptive, unlike `heroGradient`).
    static let accentGradient = LinearGradient(
        colors: [brandBlue, Color(light: 0x1E4FB8, dark: 0x60A5FA), brandGreen],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let categoryPalette: [Color] = [
        Color(light: 0x3B82F6, dark: 0x60A5FA), Color(light: 0x10B981, dark: 0x34D399),
        Color(light: 0xF97316, dark: 0xFB923C), Color(light: 0x8B5CF6, dark: 0xA78BFA),
        Color(light: 0xEC4899, dark: 0xF472B6), Color(light: 0x14B8A6, dark: 0x2DD4BF),
        Color(light: 0xF59E0B, dark: 0xFBBF24), Color(light: 0x6366F1, dark: 0x818CF8),
    ]
}

extension UIColor {
    nonisolated convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    /// Relative luminance (WCAG).
    nonisolated var luminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    // Providers must be nonisolated: SwiftUI resolves colors on its async render thread, and a
    // MainActor-isolated closure (project default isolation) traps there with a dispatch_assert_queue.
    nonisolated static func adaptive(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { @Sendable t in t.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }

    nonisolated static func adaptiveLifted(hex: UInt32) -> UIColor {
        UIColor { @Sendable t in
            let base = UIColor(hex: hex)
            return t.userInterfaceStyle == .dark ? base.liftedForDarkMode() : base
        }
    }

    /// Lightens dark arbitrary colors (backend account/category colors) so they stay visible on dark backgrounds.
    nonisolated func liftedForDarkMode() -> UIColor {
        let l = luminance
        guard l < 0.2 else { return self }
        let mix: CGFloat = l < 0.06 ? 0.5 : 0.35
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r + (1 - r) * mix, green: g + (1 - g) * mix, blue: b + (1 - b) * mix, alpha: a)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Light/dark adaptive color resolved by the current trait collection.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor.adaptive(light: light, dark: dark))
    }

    /// Parses "#RRGGBB" strings coming from the backend (category colors). Dark tones are lifted in dark mode.
    init?(hexString: String?) {
        guard var s = hexString?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(uiColor: UIColor.adaptiveLifted(hex: v))
    }
}

/// Plain grouped card (used inside scroll views where glass-on-glass would hurt legibility).
struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 24))
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).foregroundStyle(.tint) }
            Text(title).font(.headline)
            Spacer()
        }
    }
}

/// Layout helpers shared by progress bars.
nonisolated enum BarMetrics {
    /// Width for a bar filling `fraction` of `total`, clamped to [0, total] and safe for NaN/∞
    /// (SwiftUI logs "Invalid frame dimension" for negative or non-finite sizes).
    static func width(_ total: CGFloat, _ fraction: Double) -> CGFloat {
        guard total.isFinite, total > 0, fraction.isFinite else { return 0 }
        return total * CGFloat(min(max(fraction, 0), 1))
    }
}
