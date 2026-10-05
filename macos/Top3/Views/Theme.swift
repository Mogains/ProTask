import AppKit
import CoreText
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Design system
//
// Every color, size, radius, font and animation used by the views comes from here.
// Views never contain raw hex values, point sizes or durations.

enum Theme {
    // MARK: Color

    enum Palette {
        static let background = Color(nsColor: .dynamic(light: 0xFFFFFF, dark: 0x0F0F10))
        static let surface = Color(nsColor: .dynamic(light: 0xF7F7F8, dark: 0x151517))
        static let elevated = Color(nsColor: .dynamic(light: 0xEFEFF1, dark: 0x1B1B1E))
        static let border = Color(nsColor: .dynamic(light: 0xE4E4E7, dark: 0x26262A))
        static let text = Color(nsColor: .dynamic(light: 0x18181B, dark: 0xE6E6E8))
        static let textSecondary = Color(nsColor: .dynamic(light: 0x71717A, dark: 0x8A8A90))
        static let textTertiary = Color(nsColor: .dynamic(light: 0xA1A1AA, dark: 0x5A5A60))
        /// The single muted accent: checkbox fill, active indicator, drop targets.
        static let accent = Color(nsColor: .dynamic(light: 0x5B6283, dark: 0x8C93B5))
        static let accentForeground = Color(nsColor: .dynamic(light: 0xFFFFFF, dark: 0x0F0F10))
        /// Barely-there fill for hover.
        static let hover = Color(nsColor: .dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.03, darkAlpha: 0.035))
        /// Subtle fill for selection.
        static let selected = Color(nsColor: .dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.055, darkAlpha: 0.06))
        /// Faint shadow, used only on floating elements (toast, popovers).
        static let shadow = Color(nsColor: .dynamic(light: 0x000000, dark: 0x000000, lightAlpha: 0.06, darkAlpha: 0.4))

        static let nsBackground = NSColor.dynamic(light: 0xFFFFFF, dark: 0x0F0F10)
    }

    // MARK: Spacing (4pt grid)

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Radius (6 max)

    enum Radius {
        static let s: CGFloat = 4
        static let m: CGFloat = 6
    }

    // MARK: Fixed sizes

    enum Size {
        static let row: CGFloat = 32
        static let sidebarRow: CGFloat = 28
        static let header: CGFloat = 40
        static let checkbox: CGFloat = 14
        static let icon: CGFloat = 12
        static let sidebarIcon: CGFloat = 14
        static let iconButton: CGFloat = 24
        static let sidebarWidth: CGFloat = 208
        static let panelWidth: CGFloat = 264
        static let contentMaxWidth: CGFloat = 760
        static let hairline: CGFloat = 1
        static let indicator: CGFloat = 2
        static let windowMinWidth: CGFloat = 820
        static let windowMinHeight: CGFloat = 480
        static let sheetWidth: CGFloat = 460
        static let quickAddWidth: CGFloat = 400
        static let menuBarWidth: CGFloat = 300
        static let settingsWidth: CGFloat = 440
        static let estimateField: CGFloat = 48
        static let slotNumber: CGFloat = 16
        static let timeColumn: CGFloat = 52
        static let checkStroke: CGFloat = 1.5
        static let checkInset: CGFloat = 3.5
        static let dragHandle: CGFloat = 10
        static let marker: CGFloat = 2
        static let eventMarkerHeight: CGFloat = 14
        static let propertyLabel: CGFloat = 76
        static let progressSegment: CGFloat = 10
    }

    // MARK: Type

    enum TextSize {
        static let caption: CGFloat = 10
        static let secondary: CGFloat = 11
        static let small: CGFloat = 12
        static let body: CGFloat = 13
        static let input: CGFloat = 14
    }

    enum Fonts {
        static let body = Theme.font(TextSize.body)
        static let bodyMedium = Theme.font(TextSize.body, .medium)
        static let small = Theme.font(TextSize.small)
        static let smallMedium = Theme.font(TextSize.small, .medium)
        static let secondary = Theme.font(TextSize.secondary)
        static let caption = Theme.font(TextSize.caption, .medium)
        /// Tiny uppercase section label.
        static let label = Theme.font(TextSize.caption, .medium)
        static let input = Theme.font(TextSize.input)
        static let mono = Font.system(size: TextSize.secondary).monospacedDigit()
    }

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium: name = "Inter-Medium"
        case .semibold, .bold, .heavy, .black: name = "Inter-SemiBold"
        default: name = "Inter-Regular"
        }
        return Font.custom(name, fixedSize: size)
    }

    static let labelTracking: CGFloat = 0.6

    enum Opacity {
        static let past: Double = 0.45
        static let disabled: Double = 0.35
        static let pressed: Double = 0.8
    }

    // MARK: Motion (fast, subtle, no springs)

    enum Motion {
        static let hover = Animation.easeOut(duration: 0.12)
        static let standard = Animation.easeOut(duration: 0.15)
        static let list = Animation.easeOut(duration: 0.18)
        static let checkDelay: Double = 0.18
        static let toastDuration: Double = 2.8
    }

    // MARK: Fonts

    /// Registers the bundled Inter fonts for this process. Call once at launch.
    static func registerFonts() {
        for name in ["Inter-Regular", "Inter-Medium", "Inter-SemiBold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
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

// MARK: - Drag payload

extension UTType {
    static let top3Task = UTType(exportedAs: "com.anmolbhatt.top3.task")
}

/// What gets dragged around: just the task's id.
struct TaskRef: Codable, Transferable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .top3Task)
    }
}

// MARK: - Formatting

enum Fmt {
    static func due(_ t: TaskItem, today: String) -> (text: String, overdue: Bool)? {
        guard let due = t.dueDate else { return nil }
        let key = DayKey.dateKey(due)
        let day: String
        if key == today { day = "Today" }
        else if key == DayKey.adding(1, to: today) { day = "Tomorrow" }
        else if key == DayKey.adding(-1, to: today) { day = "Yesterday" }
        else { day = due.formatted(.dateTime.month(.abbreviated).day()) }
        let text = t.hasDueTime ? "\(day) \(time(due))" : day
        return (text, key < today)
    }

    static func minutes(_ m: Int?) -> String? {
        guard let m, m > 0 else { return nil }
        if m < 60 { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }

    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
}
