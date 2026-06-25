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

    // ── Elevation / shadow tokens (e1 / e2 / e3) ────────────
    enum Shadow {
        // e1 — base card shadow (two layers: crisp contact + soft lift).
        struct e1: ViewModifier {
            func body(content: Content) -> some View {
                content
                    .shadow(color: Theme.shadowInk.opacity(0.06), radius: 1, y: 1)
                    .shadow(color: Theme.shadowInk.opacity(0.09), radius: 18, y: 6)
            }
        }
        // e2 — Hero card shadow (vermillion halo + faint contact).
        struct e2: ViewModifier {
            func body(content: Content) -> some View {
                content
                    .shadow(color: Theme.accentDeep.opacity(0.45), radius: 22, y: 8)
                    .shadow(color: Theme.shadowInk.opacity(0.05), radius: 2, y: 1)
            }
        }
        // e3 — Primary button shadow (deep vermillion lift).
        struct e3: ViewModifier {
            func body(content: Content) -> some View {
                content
                    .shadow(color: Theme.accentDeep.opacity(0.55), radius: 22, x: 0, y: 10)
            }
        }
    }

    // ── Text styles (semantic font presets) ─────────────────
    // Use these instead of raw Theme.serif/.sans/.mono calls so
    // type scale stays consistent across the app.
    enum TextStyle {
        static var display:   Font { Theme.serif(28) }                  // Large title
        static var title:     Font { Theme.serif(21) }                  // Section title
        static var heroTitle: Font { Theme.sans(23, weight: .bold) }    // Hero title
        static var cardTitle: Font { Theme.sans(15, weight: .semibold) }// Card title
        static var body:      Font { Theme.sans(14) }                   // Body text
        static var small:     Font { Theme.sans(12.5) }                 // Helper text
        static var quote:     Font { Theme.serif(16).italic() }         // Reflective prompt
        static var label:     Font { Theme.mono(11) }                   // Label / time
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

// MARK: - Elevation helpers (e1 / e2 / e3)
extension View {
    func shadowE1() -> some View { modifier(Theme.Shadow.e1()) }
    func shadowE2() -> some View { modifier(Theme.Shadow.e2()) }
    func shadowE3() -> some View { modifier(Theme.Shadow.e3()) }
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
