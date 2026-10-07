import AppKit
import CoreText
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Design system
//
// Every color, size, radius, font and animation used by the views comes from here.
// Views never contain raw hex values, point sizes or durations.

enum Theme {
    /// The chosen style's colors, fonts and shapes. Views read it through the tokens below; because
    /// AppearanceStore is @Observable, any view that reads one redraws when the style, mode or accent changes.
    static var palette: ThemePalette { AppearanceStore.shared.palette }

    // MARK: Color

    enum Palette {
        static var background: Color { Theme.palette.background }
        static var surface: Color { Theme.palette.surface }
        static var elevated: Color { Theme.palette.elevated }
        static var border: Color { Theme.palette.border }
        /// Quiet marks: the empty part of a meter or chart, and the Vision grid.
        static var subtle: Color { Theme.palette.subtle }
        static var text: Color { Theme.palette.text }
        static var textSecondary: Color { Theme.palette.textSecondary }
        static var textTertiary: Color { Theme.palette.textTertiary }
        /// The single muted accent: checkbox fill, active indicator, drop targets, chart highlights.
        static var accent: Color { Theme.palette.accent }
        static var accentForeground: Color { Theme.palette.accentForeground }
        /// Barely-there fill for hover.
        static var hover: Color { Theme.palette.hover }
        /// Subtle fill for selection.
        static var selected: Color { Theme.palette.selected }
        /// Faint shadow, used only on floating elements (toast, popovers).
        static var shadow: Color { Theme.palette.shadow }

        static var nsBackground: NSColor { Theme.palette.nsBackground }
    }

    // MARK: Vision

    enum Vision {
        /// A timeline's hue: dots, bars, lane edges and data marks.
        static func color(_ c: TimelineColor) -> Color { Theme.palette.timeline[c]?.hue ?? Palette.accent }
        /// The same hue as a soft flat tint, for lane and card backgrounds.
        static func fill(_ c: TimelineColor) -> Color { Theme.palette.timeline[c]?.fill ?? Palette.hover }
        /// A bar's progress fill, ramping from `progressStart` to `progressEnd`. Set per style so bar titles stay readable.
        static func progressStart(_ c: TimelineColor) -> Color { Theme.palette.timeline[c]?.progressStart ?? Palette.selected }
        static func progressEnd(_ c: TimelineColor) -> Color { Theme.palette.timeline[c]?.progressEnd ?? Palette.selected }

        /// The small marker on active goals that are past their target date.
        static var overdue: Color { Theme.palette.overdue }
        /// A one-point top highlight on bars, for a little depth.
        static let innerHighlight = Color(nsColor: .dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.7, darkAlpha: 0.07))
        /// Lines for the finer axis unit (weeks, months), fainter than the major grid lines.
        static var gridMinor: Color { Theme.palette.gridMinor }
        /// Weekend columns at month zoom.
        static var weekend: Color { Theme.palette.weekend }
        /// The days before today, barely darker than the future.
        static let past = Color(nsColor: .dynamic(light: 0x000000, dark: 0x000000, lightAlpha: 0.012, darkAlpha: 0.12))

        /// Behind the full-size image viewer: the style's background, nearly opaque.
        static var scrim: Color { Theme.palette.scrim }

        /// Opacities applied to a timeline hue.
        enum Alpha {
            /// Bar outline.
            static let border: Double = 0.38
            static let borderHover: Double = 0.6
            /// Small progress meters (lane headers, the goal panel) ramp from this to the full hue.
            static let meterStart: Double = 0.55
            /// Dropped and idea goals in a collapsed lane.
            static let faded: Double = 0.3
            /// The lane's left edge and the line under a lane being dragged.
            static let laneEdge: Double = 0.7
            /// Today's line through the lanes.
            static let todayLine: Double = 0.7
            /// The Today label's tint in the axis.
            static let todayFill: Double = 0.14
            /// The metric graph's area: a soft ramp of the hue from the line down to nothing.
            static let areaTop: Double = 0.24
            static let areaBottom: Double = 0.0
            /// The pointer's guide line on the metric graph.
            static let chartGuide: Double = 0.5
            /// The goal panel while images are dragged over it.
            static let dropFill: Double = 0.06
        }
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
        static var s: CGFloat { Theme.palette.radiusSmall }
        static var m: CGFloat { Theme.palette.radiusMedium }
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
        /// Set per style: Mono draws thinner lines.
        static var hairline: CGFloat { Theme.palette.hairline }
        static let indicator: CGFloat = 2
        /// A standard window's corner radius, for pictures laid over a window (the appearance cross-fade).
        static let windowCorner: CGFloat = 10
        static let windowMinWidth: CGFloat = 820
        static let windowMinHeight: CGFloat = 480
        static let sheetWidth: CGFloat = 460
        static let quickAddWidth: CGFloat = 400
        static let menuBarWidth: CGFloat = 320
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
        static let capturePanelWidth: CGFloat = 560
        static let paletteWidth: CGFloat = 560
        static let paletteTopOffset: CGFloat = 96
        static let paletteMaxRows = 9
        static let wrapUpMaxHeight: CGFloat = 420
        static let sparkBar: CGFloat = 16
        static let sparkHeight: CGFloat = 48
        /// Clearance for the window's traffic lights when the sidebar is hidden.
        static let trafficLights: CGFloat = 72
        static let capturePanelHeight: CGFloat = 112
        /// AI chat panel: default width, and the range its drag handle allows.
        static let chatPanelWidth: CGFloat = 380
        static let chatPanelMinWidth: CGFloat = 300
        static let chatPanelMaxWidth: CGFloat = 720
        static let resizeHandle: CGFloat = 6
        static let chatWindowMinWidth: CGFloat = 360
        static let chatWindowMinHeight: CGFloat = 420
        static let customURLField: CGFloat = 220
        static let chatPreviewHeight: CGFloat = 280
    }

    // MARK: Vision timeline sizes

    enum Timeline {
        /// Left column with each lane's name, color and summary.
        static let laneHeaderWidth: CGFloat = 216
        /// The two-row date axis above the lanes.
        static let axisHeight: CGFloat = 44
        static let axisTier: CGFloat = 22
        static let tickMinor: CGFloat = 4
        static let tickMajor: CGFloat = 8
        /// Vertical pitch of one row of bars inside a lane.
        static let laneRow: CGFloat = 28
        static let bar: CGFloat = 22
        static let lanePadding: CGFloat = 10
        static let laneMinHeight: CGFloat = 62
        /// Extra height for each added line in a lane's header (undated goals, archived).
        static let laneHeaderLine: CGFloat = 18
        static let laneCollapsed: CGFloat = 36
        static let collapsedBar: CGFloat = 4
        static let laneEdge: CGFloat = 2
        static let laneDot: CGFloat = 8
        static let laneProgressWidth: CGFloat = 56
        static let milestone: CGFloat = 11
        static let collapsedMilestone: CGFloat = 7
        static let overdueDot: CGFloat = 5
        /// Bars never get narrower than this, so one-day goals stay clickable when zoomed out.
        static let minBarWidth: CGFloat = 8
        /// Edge zones that resize a bar.
        static let edgeHandle: CGFloat = 6
        /// Off-screen parts of long bars are cut this far past the track's edges.
        static let overscan: CGFloat = 12
        /// Goals this far outside the view still get views, so labels hanging off a bar don't pop in.
        static let cullMargin: CGFloat = 240
        /// Rough advance of one character of a bar title, for fitting labels without measuring them.
        static let labelCharWidth: CGFloat = 6.1
        static let labelPadding: CGFloat = 16
        static let percentWidth: CGFloat = 30
        static let selectionStroke: CGFloat = 1.5
        static let todayLine: CGFloat = 1.5
        /// Space kept around a goal when the view pans to show it.
        static let revealPadding: CGFloat = 48
        /// Where today sits when the board opens or jumps to today (fraction of the track from the left).
        static let todayFraction: Double = 0.3
        /// The inline title field for a goal added by double-click.
        static let promptWidth: CGFloat = 260
        /// Scroll-wheel tuning: points per line for mice, zoom per point of Cmd-scroll.
        static let scrollLine: CGFloat = 16
        static let scrollZoomRate: Double = 0.01
        /// Bounds for panning: this many years either side of today.
        static let panYears = 100
    }

    // MARK: Vision goal panel

    enum GoalPanel {
        /// The detail panel beside the board.
        static let width: CGFloat = 344
        /// The cover picture at the top of the panel.
        static let coverHeight: CGFloat = 136
        /// Image thumbnails per row.
        static let thumbColumns = 3
        /// The metric graph.
        static let chartHeight: CGFloat = 112
        static let chartLine: CGFloat = 2
        /// The end dot (and hovered dot) on the graph, with a ring in the surface color.
        static let chartDot: CGFloat = 8
        static let chartRing: CGFloat = 2
        /// Progress slider.
        static let sliderKnob: CGFloat = 14
        static let sliderHeight: CGFloat = 20
        /// Metric number fields, and the unit field beside the name.
        static let unitField: CGFloat = 72
        static let logValueField: CGFloat = 72
        /// Notes editor height range.
        static let notesMinHeight: CGFloat = 96
        static let notesMaxHeight: CGFloat = 320
        /// The rail beside update log entries.
        static let logDot: CGFloat = 7
        static let logRailWidth: CGFloat = 12
        /// The quote bar in rendered notes.
        static let quoteBar: CGFloat = 2
        /// Indent per nesting level in rendered lists.
        static let listIndent: CGFloat = 14
        /// Link and task pickers: list height.
        static let pickerListHeight: CGFloat = 288
        /// Image viewer: room around the picture, and the side buttons.
        static let viewerPadding: CGFloat = 40
        static let viewerButton: CGFloat = 32
        /// Highlight while images are dragged over the panel.
        static let dropStroke: CGFloat = 1.5
    }

    // MARK: Settings > Appearance

    enum AppearancePicker {
        /// Style cards: three across, each a small mock window above the style's name.
        static let columns = 3
        static let previewHeight: CGFloat = 76
        static let previewSidebar: CGFloat = 34
        /// Mock text lines in a preview, and their lengths as fractions of the space they sit in.
        static let line: CGFloat = 4
        static let lineLengths: [CGFloat] = [0.7, 0.5, 0.62]
        static let previewCheckbox: CGFloat = 9
        static let previewCheckStroke: CGFloat = 1.2
        static let previewCheckInset: CGFloat = 2.2
        static let selectionStroke: CGFloat = 1.5
        /// Accent swatches, with a ring around the chosen one.
        static let swatch: CGFloat = 18
        static let swatchRing: CGFloat = 1.5
        static let swatchGap: CGFloat = 3
        static let sampleText: CGFloat = 15
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
        static var body: Font { Theme.font(TextSize.body) }
        static var bodyMedium: Font { Theme.font(TextSize.body, .medium) }
        static var small: Font { Theme.font(TextSize.small) }
        static var smallMedium: Font { Theme.font(TextSize.small, .medium) }
        static var secondary: Font { Theme.font(TextSize.secondary) }
        static var caption: Font { Theme.font(TextSize.caption, .medium) }
        /// Tiny uppercase section label.
        static var label: Font { Theme.font(TextSize.caption, .medium) }
        static var input: Font { Theme.font(TextSize.input) }
        static let mono = Font.system(size: TextSize.secondary).monospacedDigit()
        /// Code in goal notes.
        static let code = Font.system(size: TextSize.secondary, design: .monospaced)
        /// Headings in rendered goal notes.
        static var heading1: Font { Theme.font(TextSize.input, .semibold) }
        static var heading2: Font { Theme.font(TextSize.body, .semibold) }
        static var heading3: Font { Theme.font(TextSize.small, .semibold) }
    }

    /// The current style's face at a size and weight.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        font(size, weight, family: Theme.palette.font)
    }

    /// A given face, for previews of styles other than the current one.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular, family: StyleFont) -> Font {
        let heavy = weight == .semibold || weight == .bold || weight == .heavy || weight == .black
        switch family {
        case .inter:
            return Font.custom(heavy ? "Inter-SemiBold" : weight == .medium ? "Inter-Medium" : "Inter-Regular", fixedSize: size)
        case .serif:
            return Font.system(size: size, weight: weight, design: .serif)
        case .humanist:
            // Seravek ships with macOS; it has no semibold, so heavier weights use its bold.
            return Font.custom(heavy ? "Seravek-Bold" : weight == .medium ? "Seravek-Medium" : "Seravek", fixedSize: size)
        }
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
        /// Zoom and jump-to-today on the Vision timeline (frames driven by VisionBoardState).
        static let timelineDuration: Double = 0.24
        static let timelineFrame: Double = 1.0 / 60
        static let toastDuration: Double = 2.8
        /// Cross-fade when the mode, style, accent or font changes.
        static let appearanceFade: Double = 0.18
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

// MARK: - Palette

/// One appearance selection turned into colors, a face and shapes. Rebuilt whenever the selection changes,
/// so every color is a new value and SwiftUI redraws what uses it. Colors still follow light and dark on their own.
struct ThemePalette {
    let background, surface, elevated, border, subtle: Color
    let text, textSecondary, textTertiary: Color
    let accent, accentForeground: Color
    let hover, selected, shadow: Color
    let scrim, gridMinor, weekend, overdue: Color
    let nsBackground: NSColor
    let timeline: [TimelineColor: TimelineHues]
    let font: StyleFont
    let radiusSmall, radiusMedium, hairline: CGFloat

    struct TimelineHues {
        let hue, fill, progressStart, progressEnd: Color
    }

    // Opacities derived from a style's own colors.
    private static let scrimAlpha: (light: CGFloat, dark: CGFloat) = (0.96, 0.94)
    private static let gridMinorAlpha: (light: CGFloat, dark: CGFloat) = (0.55, 0.55)
    private static let weekendAlpha: (light: CGFloat, dark: CGFloat) = (0.018, 0.02)

    init(_ s: AppearanceSelection) {
        let style = s.style
        func token(_ t: KeyPath<StyleTokenSet, UInt32>, alpha: (light: CGFloat, dark: CGFloat) = (1, 1)) -> Color {
            Color(nsColor: ColorTokens.color(ColorTokens.pair(style, t), alpha: alpha))
        }
        background = token(\.background)
        surface = token(\.surface)
        elevated = token(\.elevated)
        border = token(\.border)
        subtle = token(\.subtle)
        text = token(\.text)
        textSecondary = token(\.textSecondary)
        textTertiary = token(\.textTertiary)
        accent = Color(nsColor: ColorTokens.color(ColorTokens.accent(s)))
        accentForeground = Color(nsColor: ColorTokens.color(ColorTokens.accentForeground(s)))
        hover = token(\.overlay, alpha: ColorTokens.alphas(style, \.hoverAlpha))
        selected = token(\.overlay, alpha: ColorTokens.alphas(style, \.selectedAlpha))
        shadow = Color(nsColor: ColorTokens.color(StylePair(0x000000, 0x000000), alpha: ColorTokens.alphas(style, \.shadowAlpha)))
        scrim = token(\.background, alpha: Self.scrimAlpha)
        gridMinor = token(\.subtle, alpha: Self.gridMinorAlpha)
        weekend = token(\.overlay, alpha: Self.weekendAlpha)
        overdue = Color(nsColor: ColorTokens.color(StyleTokens.visionOverdue))
        nsBackground = ColorTokens.color(ColorTokens.pair(style, \.background))
        let fill = ColorTokens.alphas(style, \.barFillAlpha)
        let start = ColorTokens.alphas(style, \.progressLowAlpha), end = ColorTokens.alphas(style, \.progressHighAlpha)
        timeline = Dictionary(uniqueKeysWithValues: TimelineColor.allCases.map { c in
            let p = ColorTokens.timeline(c.rawValue)
            return (c, TimelineHues(hue: Color(nsColor: ColorTokens.color(p)),
                                    fill: Color(nsColor: ColorTokens.color(p, alpha: fill)),
                                    progressStart: Color(nsColor: ColorTokens.color(p, alpha: start)),
                                    progressEnd: Color(nsColor: ColorTokens.color(p, alpha: end))))
        })
        font = AppearanceRules.font(s)
        radiusSmall = CGFloat(style.spec.radiusSmall)
        radiusMedium = CGFloat(style.spec.radiusMedium)
        hairline = CGFloat(style.spec.hairline)
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
