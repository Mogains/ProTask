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
        static let background = Color(nsColor: ColorTokens.color(ColorTokens.background))
        static let surface = Color(nsColor: ColorTokens.color(ColorTokens.surface))
        static let elevated = Color(nsColor: ColorTokens.color(ColorTokens.elevated))
        static let border = Color(nsColor: ColorTokens.color(ColorTokens.border))
        static let text = Color(nsColor: ColorTokens.color(ColorTokens.text))
        static let textSecondary = Color(nsColor: ColorTokens.color(ColorTokens.textSecondary))
        static let textTertiary = Color(nsColor: ColorTokens.color(ColorTokens.textTertiary))
        /// The single muted accent: checkbox fill, active indicator, drop targets.
        static let accent = Color(nsColor: ColorTokens.color(ColorTokens.accent))
        static let accentForeground = Color(nsColor: ColorTokens.color(ColorTokens.accentForeground))
        /// Barely-there fill for hover.
        static let hover = Color(nsColor: .dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.03, darkAlpha: 0.035))
        /// Subtle fill for selection.
        static let selected = Color(nsColor: .dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.055, darkAlpha: 0.06))
        /// Faint shadow, used only on floating elements (toast, popovers).
        static let shadow = Color(nsColor: .dynamic(light: 0x000000, dark: 0x000000, lightAlpha: 0.06, darkAlpha: 0.4))

        static let nsBackground = ColorTokens.color(ColorTokens.background)
    }

    // MARK: Vision

    enum Vision {
        /// A timeline's hue: dots, bars, lane edges and data marks.
        static func color(_ c: TimelineColor) -> Color { colors[c] ?? Palette.accent }
        /// The same hue as a soft flat tint, for lane and card backgrounds.
        static func fill(_ c: TimelineColor) -> Color { fills[c] ?? Palette.hover }

        /// The small marker on active goals that are past their target date.
        static let overdue = Color(nsColor: ColorTokens.color(ColorTokens.visionOverdue))
        /// A one-point top highlight on bars, for a little depth.
        static let innerHighlight = Color(nsColor: .dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.7, darkAlpha: 0.07))
        /// Lines for the finer axis unit (weeks, months), fainter than the hairline border.
        static let gridMinor = Color(nsColor: .dynamic(light: ColorTokens.border.light, dark: ColorTokens.border.dark,
                                                       lightAlpha: 0.55, darkAlpha: 0.55))
        /// Weekend columns at month zoom.
        static let weekend = Color(nsColor: .dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.018, darkAlpha: 0.02))
        /// The days before today, barely darker than the future.
        static let past = Color(nsColor: .dynamic(light: 0x000000, dark: 0x000000, lightAlpha: 0.012, darkAlpha: 0.12))

        /// Behind the full-size image viewer: near-black in dark mode, near-white in light mode.
        static let scrim = Color(nsColor: .dynamic(light: 0xFAFAFA, dark: 0x0A0A0B, lightAlpha: 0.96, darkAlpha: 0.94))

        /// Opacities applied to a timeline hue.
        enum Alpha {
            /// Bar outline.
            static let border: Double = 0.38
            static let borderHover: Double = 0.6
            /// Progress fill: a soft ramp of the hue from left to right.
            static let progressLow: Double = 0.3
            static let progressHigh: Double = 0.55
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

        private static let colors: [TimelineColor: Color] = Dictionary(uniqueKeysWithValues: TimelineColor.allCases.map {
            ($0, Color(nsColor: ColorTokens.color(ColorTokens.timeline($0.rawValue))))
        })
        private static let fills: [TimelineColor: Color] = Dictionary(uniqueKeysWithValues: TimelineColor.allCases.map {
            let p = ColorTokens.timeline($0.rawValue)
            return ($0, Color(nsColor: .dynamic(light: p.light, dark: p.dark,
                                                lightAlpha: ColorTokens.timelineFillAlpha.light, darkAlpha: ColorTokens.timelineFillAlpha.dark)))
        })
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
        /// Code in goal notes.
        static let code = Font.system(size: TextSize.secondary, design: .monospaced)
        /// Headings in rendered goal notes.
        static let heading1 = Theme.font(TextSize.input, .semibold)
        static let heading2 = Theme.font(TextSize.body, .semibold)
        static let heading3 = Theme.font(TextSize.small, .semibold)
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
        /// Zoom and jump-to-today on the Vision timeline (frames driven by VisionBoardState).
        static let timelineDuration: Double = 0.24
        static let timelineFrame: Double = 1.0 / 60
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
