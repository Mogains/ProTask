import Foundation

/// WCAG 2 contrast for the appearance tokens. Run by the unit tests and by scripts/check-contrast.sh,
/// which fails the build when any style, mode and accent combination falls below its minimum.
enum Contrast {
    /// Normal-size text (WCAG AA).
    static let text = 4.5
    /// Hints, graphics and indicators: tertiary text, checkbox fills, timeline marks (WCAG AA non-text).
    static let graphic = 3.0

    /// Relative luminance of a 0xRRGGBB color, 0 (black) to 1 (white).
    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let c = Double((hex >> shift) & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    /// 1 (identical) to 21 (black on white), the same either way round.
    static func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// `color` at `alpha` over an opaque `base`, rounded to whole channel values.
    static func over(_ color: UInt32, alpha: Double, _ base: UInt32) -> UInt32 {
        func mix(_ shift: UInt32) -> UInt32 {
            let f = Double((color >> shift) & 0xFF), b = Double((base >> shift) & 0xFF)
            return UInt32((f * alpha + b * (1 - alpha)).rounded()) << shift
        }
        return mix(16) | mix(8) | mix(0)
    }

    /// One pair that must reach a minimum ratio.
    struct Pair: Equatable {
        var name: String
        var foreground: UInt32
        var background: UInt32
        var minimum: Double
        var ratio: Double { Contrast.ratio(foreground, background) }
        var passes: Bool { ratio >= minimum }
    }

    /// Every pair that matters for one style in one variant with one accent.
    static func pairs(_ s: AppearanceSelection, _ variant: StyleVariant) -> [Pair] {
        let t = AppearanceRules.tokens(s.style, variant)
        let selected = over(t.overlay, alpha: t.selectedAlpha, t.background)
        let surfaces: [(String, UInt32)] = [("background", t.background), ("surface", t.surface),
                                            ("elevated", t.elevated), ("selected row", selected)]
        var out: [Pair] = []
        func add(_ name: String, _ fg: UInt32, _ bg: UInt32, _ min: Double) {
            out.append(Pair(name: name, foreground: fg, background: bg, minimum: min))
        }
        for (name, bg) in surfaces {
            add("text on \(name)", t.text, bg, text)
            add("secondary text on \(name)", t.textSecondary, bg, text)
        }
        for (name, bg) in surfaces.prefix(3) {
            add("tertiary text on \(name)", t.textTertiary, bg, graphic)
        }
        // The accent is also used as link text, so it needs text contrast on the main surfaces.
        let accent = AppearanceRules.accentColor(s, variant)
        let accentName = AppearanceRules.accent(s)?.title ?? "text-colored"
        add("\(accentName) accent on background", accent, t.background, text)
        add("\(accentName) accent on surface", accent, t.surface, text)
        add("\(accentName) accent on elevated", accent, t.elevated, graphic)
        add("\(accentName) accent on selected row", accent, selected, graphic)
        add("check mark on \(accentName) accent", AppearanceRules.accentForeground(s, variant), accent, text)
        // Filled and empty parts of a meter (the Top 3 segments) must be told apart, and Today's line from the grid.
        add("\(accentName) accent on subtle marks", accent, t.subtle, graphic)
        // Vision: marks on the board, and bar titles over the tint and the strongest part of the progress fill.
        for (hueName, pair) in StyleTokens.timelinePalette.sorted(by: { $0.key < $1.key }) {
            let hue = pair.value(variant)
            add("\(hueName) timeline mark on background", hue, t.background, graphic)
            add("\(hueName) timeline mark on surface", hue, t.surface, graphic)
            let tint = over(hue, alpha: t.barFillAlpha, t.background)
            add("text on \(hueName) bar", t.text, tint, text)
            add("text on \(hueName) progress", t.text, over(hue, alpha: t.progressHighAlpha, tint), text)
        }
        add("overdue marker on background", StyleTokens.visionOverdue.value(variant), t.background, graphic)
        return out
    }

    /// Every style in every variant it has, with every accent it offers.
    static func allSelections() -> [(AppearanceSelection, StyleVariant)] {
        AppearanceStyle.allCases.flatMap { style -> [(AppearanceSelection, StyleVariant)] in
            let variants = StyleVariant.allCases.filter { v in v == .light ? style.spec.light != nil : style.spec.dark != nil }
            let accents: [AccentChoice?] = AppearanceRules.hasAccent(style) ? AccentChoice.allCases : [nil]
            return variants.flatMap { v in accents.map { (AppearanceSelection(style: style, accent: $0), v) } }
        }
    }

    /// One line per failing pair, e.g. "Sand light, Teal: Teal accent on surface is 4.43:1, needs 4.5:1".
    static func violations() -> [String] {
        allSelections().flatMap { s, v in
            pairs(s, v).filter { !$0.passes }.map { p in
                let accent = AppearanceRules.accent(s).map { ", \($0.title)" } ?? ""
                return "\(s.style.title) \(v.rawValue)\(accent): \(p.name) is \(format(p.ratio)):1, needs \(format(p.minimum)):1"
            }
        }
    }

    private static func format(_ x: Double) -> String { String(format: "%.2f", x) }
}
