import SwiftUI

enum Theme {
    // Grounds & surfaces — warm cream palette (refined for depth & contrast)
    static let bg      = Color(hex: "ece5d6")   // app ground (warm cream)
    static let paper   = Color(hex: "ece5d6")   // alias kept for compatibility
    static let bgWarm  = Color(hex: "f1ebdd")   // recessed wells / input bg
    static let surface = Color(hex: "f8f3e9")   // cards / sheets
    static let surface2 = Color(hex: "fdfaf3")  // raised / active surface (now distinct)

    // Ink — warm, never pure black (deepened for stronger contrast)
    static let ink     = Color(hex: "1d2236")
    static let inkSoft = Color(hex: "4e5064")
    static let muted   = Color(hex: "7d7665")
    static let faint   = Color(hex: "c2b9a4")

    // Separators
    static let line    = Color(hex: "1d2236").opacity(0.10)
    static let line2   = Color(hex: "1d2236").opacity(0.06)

    // Shadow ink (warm) — used by elevation helpers below
    static let shadowInk = Color(hex: "1d2236")

    // Accent — Vermillion (#c75d2c). Rationed: always means "now / act".
    static let accent      = Color(hex: "c75d2c")
    static let accentSoft  = Color(hex: "e7a06a")
    static let accentWash  = Color(hex: "c75d2c").opacity(0.10)
    static let accentRing  = Color(hex: "c75d2c").opacity(0.22)
    static let accentDeep  = Color(hex: "a8542f")

    // Priority — earthy, never neon
    static let prioLow  = Color(hex: "6f9a6b")   // sage
    static let prioMed  = Color(hex: "d39a3f")   // amber
    static let prioHigh = Color(hex: "c2502f")   // clay

    // Warning text — deep amber for "overdue / low energy / needs review" copy.
    static let amberText = Color(hex: "a87320")
    // Surface tint for overdue cards (warm amber-washed paper).
    static let overdueSurface = Color(hex: "f7ecdf")

    // ── Spacing (8 pt rhythm) ───────────────────────────────
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // ── Corner radius scale ─────────────────────────────────
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let card: CGFloat = 16
        static let lg: CGFloat = 18
        static let hero: CGFloat = 22
    }

    // `relativeTo:` keeps custom fonts scaling with Dynamic Type.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        font(
            named: "LibreCaslonText-Regular",
            size: size,
            weight: weight,
            fallbackDesign: .serif
        )
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        font(
            named: "Inter-Regular",
            size: size,
            weight: weight,
            fallbackDesign: .default
        )
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        font(
            named: "JetBrainsMono-Regular",
            size: size,
            weight: weight,
            fallbackDesign: .monospaced
        )
    }

    private static func font(
        named name: String,
        size: CGFloat,
        weight: Font.Weight,
        fallbackDesign: Font.Design
    ) -> Font {
        if Bundle.main.url(forResource: name, withExtension: "ttf") != nil
            || Bundle.main.url(forResource: name, withExtension: "otf") != nil {
            return .custom(name, size: size, relativeTo: relativeStyle(for: size)).weight(weight)
        }

        return .system(size: size, weight: weight, design: fallbackDesign)
    }

    private static func relativeStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<12: .caption2
        case ..<14: .caption
        case ..<16: .subheadline
        case ..<18: .body
        case ..<24: .title3
        case ..<30: .title2
        case ..<38: .title
        default: .largeTitle
        }
    }

    static func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "low":
            prioLow
        case "high":
            prioHigh
        default:
            prioMed
        }
    }
}

extension Color {
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }

        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
