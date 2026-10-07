import Foundation

// MARK: - Appearance tokens
//
// Every style's raw values as plain numbers, shared by the app, the widget, the unit tests and the
// contrast check that runs during the build (scripts/check-contrast.sh). Pure Swift: no AppKit or SwiftUI.
// Theme turns these into colors, fonts and radii; views never read them directly.

/// Light, dark, or whatever the system uses.
enum AppearanceMode: String, CaseIterable, Codable, Sendable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// One of a style's two token sets.
enum StyleVariant: String, CaseIterable, Sendable {
    case light, dark
}

/// The app's typeface. Inter is bundled; the serif is the system's New York; the humanist is Seravek.
enum StyleFont: String, CaseIterable, Codable, Sendable {
    case inter, serif, humanist

    var title: String {
        switch self {
        case .inter: "Inter"
        case .serif: "Serif"
        case .humanist: "Humanist"
        }
    }
}

/// The accent options: muted, and each with a tone for light backgrounds and one for dark.
/// Applied to checkboxes, selection indicators, links and chart highlights.
enum AccentChoice: String, CaseIterable, Codable, Sendable {
    case iris, blue, teal, sage, ochre, clay, rose, plum

    var title: String { rawValue.capitalized }

    var tones: StylePair {
        switch self {
        case .iris: StylePair(0x5B6283, 0x8C93B5)
        case .blue: StylePair(0x48658A, 0x86A1C8)
        case .teal: StylePair(0x386A6A, 0x7EAAA8)
        case .sage: StylePair(0x4F6A49, 0x93AE8C)
        case .ochre: StylePair(0x76632F, 0xBCA46C)
        case .clay: StylePair(0x8C543B, 0xCB957B)
        case .rose: StylePair(0x8F5565, 0xC690A0)
        case .plum: StylePair(0x6B5C8C, 0xA899C6)
        }
    }
}

/// A light and a dark value.
struct StylePair: Equatable, Sendable {
    var light: UInt32
    var dark: UInt32
    init(_ light: UInt32, _ dark: UInt32) { self.light = light; self.dark = dark }
    func value(_ variant: StyleVariant) -> UInt32 { variant == .light ? light : dark }
}

/// One full set of colors for a style in one variant. Overlays (hover, selection) are the overlay color at an alpha.
struct StyleTokenSet: Equatable, Sendable {
    var background: UInt32
    var surface: UInt32
    var elevated: UInt32
    var border: UInt32
    /// Quiet marks: the empty part of a meter or chart and the Vision board's grid. The border color,
    /// except in Mono, whose full black or white borders would drown out the accent there.
    var subtle: UInt32
    var text: UInt32
    var textSecondary: UInt32
    /// Hints, counts and section labels. Held to 3:1, not 4.5:1, so it stays a step below secondary text.
    var textTertiary: UInt32
    var overlay: UInt32
    var hoverAlpha: Double
    var selectedAlpha: Double
    var shadowAlpha: Double
    /// Vision bars: the hue's tint behind the title, and the progress fill's ramp from left to right.
    var barFillAlpha: Double
    var progressLowAlpha: Double
    var progressHighAlpha: Double
}

/// A style: its token sets, accent, shape and type.
struct StyleSpec: Sendable {
    var light: StyleTokenSet?
    var dark: StyleTokenSet?
    /// Nil for a style without an accent (Mono), which uses its text color instead.
    var defaultAccent: AccentChoice?
    var radiusSmall: Double
    var radiusMedium: Double
    var hairline: Double
    /// The first is the default; more than one shows a font picker.
    var fonts: [StyleFont]
}

enum AppearanceStyle: String, CaseIterable, Codable, Sendable {
    case graphite, paper, midnight, mono, sand, slate

    var title: String { rawValue.capitalized }

    var blurb: String {
        switch self {
        case .graphite: "Neutral greys, the default"
        case .paper: "Warm off-white, book-like"
        case .midnight: "Navy-black, blue accent"
        case .mono: "Pure black and white"
        case .sand: "Warm greys, earthy accent"
        case .slate: "Mid-dark cool grey, softer"
        }
    }

    var spec: StyleSpec {
        switch self {
        case .graphite: StyleTokens.graphite
        case .paper: StyleTokens.paper
        case .midnight: StyleTokens.midnight
        case .mono: StyleTokens.mono
        case .sand: StyleTokens.sand
        case .slate: StyleTokens.slate
        }
    }
}

// MARK: - Values

enum StyleTokens {
    // Bar alphas most styles share.
    private static let lightBars = (fill: 0.15, low: 0.30, high: 0.55)
    private static let darkBars = (fill: 0.18, low: 0.30, high: 0.42)

    private static func set(_ bg: UInt32, _ surface: UInt32, _ elevated: UInt32, _ border: UInt32,
                            _ text: UInt32, _ secondary: UInt32, _ tertiary: UInt32, overlay: UInt32,
                            hover: Double, selected: Double, shadow: Double,
                            bars: (fill: Double, low: Double, high: Double), subtle: UInt32? = nil) -> StyleTokenSet {
        StyleTokenSet(background: bg, surface: surface, elevated: elevated, border: border, subtle: subtle ?? border, text: text,
                      textSecondary: secondary, textTertiary: tertiary, overlay: overlay, hoverAlpha: hover,
                      selectedAlpha: selected, shadowAlpha: shadow, barFillAlpha: bars.fill,
                      progressLowAlpha: bars.low, progressHighAlpha: bars.high)
    }

    /// Black, white and greys.
    static let graphite = StyleSpec(
        light: set(0xFFFFFF, 0xF7F7F8, 0xEFEFF1, 0xE4E4E7, 0x18181B, 0x6A6A72, 0x87878F, overlay: 0x000000,
                   hover: 0.03, selected: 0.055, shadow: 0.06, bars: lightBars),
        dark: set(0x0F0F10, 0x151517, 0x1B1B1E, 0x26262A, 0xE6E6E8, 0x8A8A90, 0x6E6E75, overlay: 0xFFFFFF,
                  hover: 0.035, selected: 0.06, shadow: 0.4, bars: darkBars),
        defaultAccent: .iris, radiusSmall: 4, radiusMedium: 6, hairline: 1, fonts: [.inter])

    /// Warm off-white with soft grey lines and a reading face; a warm sepia at night.
    static let paper = StyleSpec(
        light: set(0xFBF8F2, 0xF5F1E8, 0xEDE8DC, 0xE2DBCC, 0x2B2722, 0x655D52, 0x857C6F, overlay: 0x3A2E1F,
                   hover: 0.035, selected: 0.06, shadow: 0.06, bars: lightBars),
        dark: set(0x1B1916, 0x211F1B, 0x292621, 0x37332C, 0xE8E1D4, 0xA39A8B, 0x81796B, overlay: 0xFFF3DD,
                  hover: 0.035, selected: 0.06, shadow: 0.4, bars: darkBars),
        defaultAccent: .sage, radiusSmall: 3, radiusMedium: 5, hairline: 1, fonts: [.serif, .humanist])

    /// Deep navy-black, cool grey text, one muted blue. Dark only.
    static let midnight = StyleSpec(
        light: nil,
        dark: set(0x0B1020, 0x10162A, 0x161D34, 0x232B44, 0xDCE2EE, 0x8F99AF, 0x6C7690, overlay: 0xCFDDFF,
                  hover: 0.04, selected: 0.07, shadow: 0.5, bars: darkBars),
        defaultAccent: .blue, radiusSmall: 4, radiusMedium: 6, hairline: 1, fonts: [.inter])

    /// Pure black and white, thin lines, no accent.
    static let mono = StyleSpec(
        light: set(0xFFFFFF, 0xFFFFFF, 0xF2F2F2, 0x000000, 0x000000, 0x4A4A4A, 0x6B6B6B, overlay: 0x000000,
                   hover: 0.04, selected: 0.07, shadow: 0.1, bars: lightBars, subtle: 0xD6D6D6),
        dark: set(0x000000, 0x000000, 0x141414, 0xFFFFFF, 0xFFFFFF, 0xB3B3B3, 0x8F8F8F, overlay: 0xFFFFFF,
                  hover: 0.06, selected: 0.1, shadow: 0.5, bars: darkBars, subtle: 0x3A3A3A),
        defaultAccent: nil, radiusSmall: 2, radiusMedium: 3, hairline: 0.5, fonts: [.inter])

    /// Light warm greys with a muted earthy accent.
    static let sand = StyleSpec(
        light: set(0xF3F0EA, 0xEDE9E1, 0xE6E1D7, 0xD9D2C5, 0x29251F, 0x5F574C, 0x7E7567, overlay: 0x3A2E1F,
                   hover: 0.04, selected: 0.065, shadow: 0.07, bars: lightBars),
        dark: set(0x1E1C19, 0x25221E, 0x2D2A25, 0x3B3730, 0xE4DED3, 0xA49B8D, 0x82796B, overlay: 0xFFF3DD,
                  hover: 0.04, selected: 0.065, shadow: 0.4, bars: (fill: 0.18, low: 0.28, high: 0.38)),
        defaultAccent: .clay, radiusSmall: 5, radiusMedium: 6, hairline: 1, fonts: [.inter])

    /// Mid-dark cool grey, softer contrast than Graphite; a cool light grey by day.
    static let slate = StyleSpec(
        light: set(0xE8EBEF, 0xE2E6EB, 0xDAE0E6, 0xCBD2DB, 0x2A2F37, 0x535A65, 0x6E7682, overlay: 0x1E2836,
                   hover: 0.04, selected: 0.065, shadow: 0.08, bars: lightBars),
        dark: set(0x212429, 0x262A30, 0x2D3138, 0x393E47, 0xD3D8DF, 0x9AA1AD, 0x7F8692, overlay: 0xDCE6F5,
                  hover: 0.04, selected: 0.065, shadow: 0.4, bars: (fill: 0.18, low: 0.22, high: 0.30)),
        defaultAccent: .teal, radiusSmall: 4, radiusMedium: 6, hairline: 1, fonts: [.inter])

    // MARK: Vision timeline palette
    // Eight low-saturation hues keyed by TimelineColor name, the same in every style.
    // The contrast check holds each to 3:1 on every style's background.

    static let timelinePalette: [String: StylePair] = [
        "slate": StylePair(0x5F7088, 0x8F9EB3),
        "mist": StylePair(0x4F7A7B, 0x80A8A7),
        "sage": StylePair(0x5D7A5B, 0x8FAA8B),
        "sand": StylePair(0x7F744A, 0xB0A47A),
        "clay": StylePair(0x96664D, 0xC09379),
        "rose": StylePair(0x93606B, 0xBE8C96),
        "plum": StylePair(0x73668E, 0xA497BD),
        "stone": StylePair(0x6F6B66, 0x9F9B95),
    ]
    static let timelineFallback = StylePair(0x5F7088, 0x8F9EB3)
    /// A muted terracotta for the small marker on active goals past their target date.
    static let visionOverdue = StylePair(0xA35F4C, 0xC98D79)
}

// MARK: - Rules

/// What the user picked: kept as chosen, even when the current style can't honor all of it,
/// so switching back to a style that can restores it.
struct AppearanceSelection: Equatable, Codable, Sendable {
    var mode: AppearanceMode = .system
    var style: AppearanceStyle = .graphite
    /// Nil follows the style's own accent.
    var accent: AccentChoice?
    /// Nil uses the style's default face.
    var font: StyleFont?

    static let `default` = AppearanceSelection()

    init(mode: AppearanceMode = .system, style: AppearanceStyle = .graphite, accent: AccentChoice? = nil, font: StyleFont? = nil) {
        self.mode = mode
        self.style = style
        self.accent = accent
        self.font = font
    }

    /// Unknown values (say, a style from a newer version) fall back to the defaults instead of failing the whole file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func raw(_ key: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil }
        mode = raw(.mode).flatMap(AppearanceMode.init) ?? .system
        style = raw(.style).flatMap(AppearanceStyle.init) ?? .graphite
        accent = raw(.accent).flatMap(AccentChoice.init)
        font = raw(.font).flatMap(StyleFont.init)
    }
}

enum AppearanceRules {
    /// The modes a style offers. A single-variant style offers only that one.
    static func modes(for style: AppearanceStyle) -> [AppearanceMode] {
        let spec = style.spec
        switch (spec.light != nil, spec.dark != nil) {
        case (true, true): return AppearanceMode.allCases
        case (true, false): return [.light]
        default: return [.dark]
        }
    }

    /// The mode actually applied: the chosen one when the style has it, otherwise the style's only one.
    static func effectiveMode(_ s: AppearanceSelection) -> AppearanceMode {
        let modes = modes(for: s.style)
        return modes.contains(s.mode) ? s.mode : modes[0]
    }

    /// The token set for a variant, falling back to the style's only one.
    static func tokens(_ style: AppearanceStyle, _ variant: StyleVariant) -> StyleTokenSet {
        let spec = style.spec
        switch variant {
        case .light: return spec.light ?? spec.dark!
        case .dark: return spec.dark ?? spec.light!
        }
    }

    /// Nil when the style has no accent.
    static func accent(_ s: AppearanceSelection) -> AccentChoice? {
        guard let fallback = s.style.spec.defaultAccent else { return nil }
        return s.accent ?? fallback
    }

    static func hasAccent(_ style: AppearanceStyle) -> Bool { style.spec.defaultAccent != nil }

    static func font(_ s: AppearanceSelection) -> StyleFont {
        let fonts = s.style.spec.fonts
        if let f = s.font, fonts.contains(f) { return f }
        return fonts[0]
    }

    /// The accent color in a variant; the text color for a style without an accent.
    static func accentColor(_ s: AppearanceSelection, _ variant: StyleVariant) -> UInt32 {
        guard let accent = accent(s) else { return tokens(s.style, variant).text }
        return accent.tones.value(variant)
    }

    /// What sits on a filled accent (the check mark): white on light-mode accents, the background on dark ones,
    /// and the background on a style whose accent is its text color.
    static func accentForeground(_ s: AppearanceSelection, _ variant: StyleVariant) -> UInt32 {
        let t = tokens(s.style, variant)
        if accent(s) == nil { return t.background }
        return variant == .light ? 0xFFFFFF : t.background
    }
}
