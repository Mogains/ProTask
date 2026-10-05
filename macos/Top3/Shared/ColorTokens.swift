import AppKit

/// The palette's raw values, shared by the app and the widget. Views use Theme.Palette, never these directly.
enum ColorTokens {
    typealias Pair = (light: UInt32, dark: UInt32)
    static let background: Pair = (0xFFFFFF, 0x0F0F10)
    static let surface: Pair = (0xF7F7F8, 0x151517)
    static let elevated: Pair = (0xEFEFF1, 0x1B1B1E)
    static let border: Pair = (0xE4E4E7, 0x26262A)
    static let text: Pair = (0x18181B, 0xE6E6E8)
    static let textSecondary: Pair = (0x71717A, 0x8A8A90)
    static let textTertiary: Pair = (0xA1A1AA, 0x5A5A60)
    static let accent: Pair = (0x5B6283, 0x8C93B5)
    static let accentForeground: Pair = (0xFFFFFF, 0x0F0F10)

    static func color(_ p: Pair) -> NSColor { .dynamic(light: p.light, dark: p.dark) }
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
