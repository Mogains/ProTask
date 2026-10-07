import AppKit

/// Turns the appearance tokens (StyleTokens) into AppKit colors, for the app and the widget.
/// Views use Theme.Palette, never these directly.
enum ColorTokens {
    /// One token of a style as a light and dark pair. A single-variant style gives the same value for both.
    static func pair(_ style: AppearanceStyle, _ token: KeyPath<StyleTokenSet, UInt32>) -> StylePair {
        StylePair(AppearanceRules.tokens(style, .light)[keyPath: token], AppearanceRules.tokens(style, .dark)[keyPath: token])
    }

    /// One alpha of a style as a light and dark pair.
    static func alphas(_ style: AppearanceStyle, _ token: KeyPath<StyleTokenSet, Double>) -> (light: CGFloat, dark: CGFloat) {
        (CGFloat(AppearanceRules.tokens(style, .light)[keyPath: token]), CGFloat(AppearanceRules.tokens(style, .dark)[keyPath: token]))
    }

    static func accent(_ s: AppearanceSelection) -> StylePair {
        StylePair(AppearanceRules.accentColor(s, .light), AppearanceRules.accentColor(s, .dark))
    }

    static func accentForeground(_ s: AppearanceSelection) -> StylePair {
        StylePair(AppearanceRules.accentForeground(s, .light), AppearanceRules.accentForeground(s, .dark))
    }

    static func timeline(_ name: String) -> StylePair { StyleTokens.timelinePalette[name] ?? StyleTokens.timelineFallback }

    /// A color that follows the appearance it is drawn in.
    static func color(_ p: StylePair, alpha: (light: CGFloat, dark: CGFloat) = (1, 1)) -> NSColor {
        .dynamic(light: p.light, dark: p.dark, lightAlpha: alpha.light, darkAlpha: alpha.dark)
    }

    /// The same pair fixed to one variant, for places that can't follow the appearance (a widget with a forced mode).
    static func color(_ p: StylePair, fixed variant: StyleVariant) -> NSColor { NSColor(hex: p.value(variant)) }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    /// A color that follows the system light/dark appearance.
    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: dark, alpha: darkAlpha)
                : NSColor(hex: light, alpha: lightAlpha)
        }
    }
}
