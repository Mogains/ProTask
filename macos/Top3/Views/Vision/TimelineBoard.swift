import AppKit
import SwiftUI

// MARK: - Shared geometry

/// Bar, marker and row geometry shared by the board, its lanes and the marks, so packing and drawing agree.
enum TimelineMetrics {
    static func labelWidth(_ title: String) -> CGFloat {
        CGFloat(TimelinePacking.estimatedLabelWidth(title, characterWidth: Double(Theme.Timeline.labelCharWidth),
                                                    padding: Double(Theme.Timeline.labelPadding)))
    }

    /// Active goals (and open goals with some progress) show their percentage on the bar.
    static func showsPercent(_ g: TimelineGoal) -> Bool {
        g.status == .active || (g.status.isOpen && g.progress > 0)
    }

    /// The bar's full extent on the track (never narrower than the minimum).
    static func barExtent(_ span: DaySpan, scale: TimelineScale, calendar: Calendar) -> (x0: CGFloat, x1: CGFloat) {
        let x0 = CGFloat(scale.x(span.start))
        let x1 = max(CGFloat(scale.x(span.visualEnd(calendar: calendar))), x0 + Theme.Timeline.minBarWidth)
        return (x0, x1)
    }

    /// The middle of a milestone's day.
    static func milestoneCenter(_ span: DaySpan, scale: TimelineScale) -> CGFloat {
        CGFloat(scale.x(span.start) + scale.pointsPerDay / 2)
    }

    /// What goes inside a bar: title and percentage, the title alone, or nothing (the title hangs outside).
    enum LabelFit { case full, titleOnly, outside }

    static func labelFit(barWidth: CGFloat, goal: TimelineGoal) -> LabelFit {
        let title = labelWidth(goal.title)
        if barWidth >= title + (showsPercent(goal) ? Theme.Timeline.percentWidth : 0) { return .full }
        return barWidth >= title ? .titleOnly : .outside
    }

    /// Top of a row's bar inside a lane.
    static func barY(row: Int) -> CGFloat {
        Theme.Timeline.lanePadding + CGFloat(row) * Theme.Timeline.laneRow + (Theme.Timeline.laneRow - Theme.Timeline.bar) / 2
    }

    /// The space a goal takes in its row, including a label that hangs outside its bar and the overdue dot.
    static func packingItem(_ g: PlacedGoal, scale: TimelineScale, calendar: Calendar) -> TimelinePacking.Item? {
        guard let span = g.span else { return nil }
        let dot = g.overdue ? Theme.Timeline.overdueDot + Theme.Space.xs : 0
        if g.goal.isMilestone {
            let c = milestoneCenter(span, scale: scale)
            let half = Theme.Timeline.milestone / 2
            return .init(id: g.id, x0: Double(c - half), x1: Double(c + half + dot + Theme.Space.xs + labelWidth(g.goal.title)))
        }
        let (x0, x1) = barExtent(span, scale: scale, calendar: calendar)
        let outside = labelFit(barWidth: x1 - x0, goal: g.goal) == .outside ? Theme.Space.xs + labelWidth(g.goal.title) : 0
        return .init(id: g.id, x0: Double(x0), x1: Double(x1 + dot + outside))
    }

    struct LaneLayout: Equatable {
        var rows: [UUID: Int] = [:]
        var rowCount = 1
        var height: CGFloat = Theme.Timeline.laneMinHeight
        /// The row the inline title field sits in, when a goal is being added to this lane.
        var promptRow: Int?
    }

    /// `archived` adds a line to the header, as undated goals do.
    static func layout(_ goals: [PlacedGoal], scale: TimelineScale, collapsed: Bool, pending: Bool, archived: Bool = false,
                       calendar: Calendar) -> LaneLayout {
        if collapsed { return LaneLayout(rows: [:], rowCount: 1, height: Theme.Timeline.laneCollapsed, promptRow: nil) }
        let rows = TimelinePacking.rows(goals.compactMap { packingItem($0, scale: scale, calendar: calendar) }, gap: Double(Theme.Space.s))
        let used = TimelinePacking.rowCount(rows)
        let shown = max(used + (pending ? 1 : 0), 1)
        let lines = (goals.contains { $0.span == nil } ? 1 : 0) + (archived ? 1 : 0)
        let header = Theme.Timeline.laneMinHeight + CGFloat(lines) * Theme.Timeline.laneHeaderLine
        let height = max(header, Theme.Timeline.lanePadding * 2 + CGFloat(shown) * Theme.Timeline.laneRow)
        return LaneLayout(rows: rows, rowCount: shown, height: height, promptRow: pending ? used : nil)
    }
}

enum VisionFormat {
    /// "Mar 4" this year, "Mar 4, 2028" otherwise.
    static func day(_ d: Date) -> String {
        let sameYear = Calendar.current.isDate(d, equalTo: Date(), toGranularity: .year)
        return sameYear ? d.formatted(.dateTime.month(.abbreviated).day()) : d.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func span(_ s: DaySpan) -> String {
        s.isSingleDay ? day(s.start) : "\(day(s.start)) – \(day(s.end))"
    }
}

// MARK: - Board

/// Lanes stacked under a shared date axis. The left column holds each lane's header; the track scrolls in time.
///
/// Pan: drag empty space, scroll sideways (or Shift-scroll). Zoom: pinch, Cmd-scroll, Cmd= / Cmd-, or + and -.
/// Keys: arrows move between goals, Option-arrows move the selected goal (Shift-Option resizes its end),
/// Return opens it, Delete asks to delete it, Esc closes.
struct TimelineBoard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let lanes: [LaneInfo]
    let goals: [UUID: [PlacedGoal]]
    let archivedCount: Int

    @FocusState private var focused: Bool
    @State private var laneDrag: LaneDrag?

    struct LaneDrag: Equatable {
        var id: UUID
        var offset: CGFloat
    }

    private var headerWidth: CGFloat { Theme.Timeline.laneHeaderWidth + Theme.Size.hairline }

    var body: some View {
        let board = model.visionBoard
        GeometryReader { geo in
            let width = max(geo.size.width - headerWidth, 0)
            let cal = Calendar.current
            let scale = board.scale
            let axis = TimelineAxis.make(for: scale.visibleInterval(width: Double(width)), pointsPerDay: scale.pointsPerDay, calendar: cal)
            let layouts = lanes.map { lane in
                TimelineMetrics.layout(goals[lane.id] ?? [], scale: scale, collapsed: board.isCollapsed(lane.id),
                                       pending: board.pending?.laneID == lane.id, archived: lane.archived, calendar: cal)
            }
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        AxisCorner()
                            .frame(width: Theme.Timeline.laneHeaderWidth, height: Theme.Timeline.axisHeight)
                            .background(Theme.Palette.surface)
                        Hairline(vertical: true)
                        TimelineAxisView(axis: axis, scale: scale, width: width)
                            .frame(width: width, height: Theme.Timeline.axisHeight)
                    }
                    .frame(height: Theme.Timeline.axisHeight)
                    Hairline()
                    ScrollView(.vertical) {
                        lanesStack(layouts: layouts, scale: scale, axis: axis, width: width)
                    }
                    .scrollIndicators(.automatic)
                }
                .focusable()
                .focused($focused)
                .focusEffectDisabled()
                .onKeyPress(phases: .down) { press in handleKey(press, proxy: proxy, width: width) }
            }
            .background(TimelineScrollMonitor { event, point, horizontal in
                handleScroll(event, at: point, horizontal: horizontal)
            })
            .simultaneousGesture(pinch)
            .onAppear {
                board.updateWidth(Double(width))
                focused = true
            }
            .onChange(of: width) { board.updateWidth(Double(width)) }
            .onChange(of: board.focusRequest) { focused = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Vision timeline")
    }

    // MARK: Lanes

    @ViewBuilder
    private func lanesStack(layouts: [TimelineMetrics.LaneLayout], scale: TimelineScale, axis: TimelineAxis, width: CGFloat) -> some View {
        let target = laneDrag.flatMap { drag in
            lanes.firstIndex { $0.id == drag.id }.map { from in
                (from: from, to: LaneReorder.targetIndex(from: from, offset: Double(drag.offset),
                                                         heights: layouts.map { Double($0.height + Theme.Size.hairline) }))
            }
        }
        VStack(spacing: 0) {
            ForEach(Array(lanes.enumerated()), id: \.element.id) { index, lane in
                let dragging = laneDrag?.id == lane.id
                VStack(spacing: 0) {
                    TimelineLaneRow(lane: lane, index: index, laneCount: lanes.count, goals: goals[lane.id] ?? [],
                                    layout: layouts[index], scale: scale, axis: axis, trackWidth: width,
                                    onReorderDrag: { offset in laneDrag = LaneDrag(id: lane.id, offset: offset) },
                                    onReorderEnd: { offset in finishLaneDrag(lane.id, offset: offset, layouts: layouts) })
                    Hairline()
                }
                // Opaque, so a lane being dragged covers the lanes it passes over.
                .background(dragging ? Theme.Palette.elevated : Theme.Palette.background)
                .overlay(alignment: .top) {
                    if let t = target, t.to == index, t.to < t.from { InsertionLine(visible: true) }
                }
                .overlay(alignment: .bottom) {
                    if let t = target, t.to == index, t.to > t.from { InsertionLine(visible: true) }
                }
                .offset(y: dragging ? laneDrag?.offset ?? 0 : 0)
                .zIndex(dragging ? 1 : 0)
                .shadow(color: dragging ? Theme.Palette.shadow : .clear, radius: dragging ? Theme.Space.s : 0, y: dragging ? Theme.Space.xxs : 0)
                .id(lane.id)
            }
            if lanes.isEmpty {
                EmptyLine(text: "Every timeline is archived.")
                    .padding(.horizontal, Theme.Space.l)
            }
            if archivedCount > 0 {
                HStack {
                    Button(model.visionBoard.showArchived ? "Hide archived" : "Show archived (\(archivedCount))") {
                        model.visionBoard.setShowArchived(!model.visionBoard.showArchived)
                    }
                    .buttonStyle(.ghost)
                    Spacer()
                }
                .padding(.horizontal, Theme.Space.s)
                .padding(.vertical, Theme.Space.s)
            }
        }
    }

    private func finishLaneDrag(_ id: UUID, offset: CGFloat, layouts: [TimelineMetrics.LaneLayout]) {
        defer { laneDrag = nil }
        guard let from = lanes.firstIndex(where: { $0.id == id }) else { return }
        let to = LaneReorder.targetIndex(from: from, offset: Double(offset), heights: layouts.map { Double($0.height + Theme.Size.hairline) })
        guard to != from else { return }
        model.moveTimeline(id, before: LaneReorder.beforeID(moving: from, to: to, ids: lanes.map(\.id)))
    }

    // MARK: Pinch and scroll

    private var pinch: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                let board = model.visionBoard
                if board.gestureStart == nil { board.gestureStart = board.scale }
                guard let start = board.gestureStart else { return }
                board.setScale(start.zoomed(by: value.magnification, anchorX: Double(value.startLocation.x - headerWidth)))
            }
            .onEnded { _ in
                model.visionBoard.gestureStart = nil
                model.visionBoard.saveZoom()
            }
    }

    /// Sideways scrolling pans; Cmd-scroll zooms around the pointer; plain vertical scrolling goes to the lanes.
    private func handleScroll(_ event: NSEvent, at point: CGPoint, horizontal: Bool) -> Bool {
        let board = model.visionBoard
        let line = event.hasPreciseScrollingDeltas ? 1 : Double(Theme.Timeline.scrollLine)
        if event.modifierFlags.contains(.command) {
            let delta = Double(event.scrollingDeltaY) * line
            guard delta != 0 else { return true }
            board.setScale(board.scale.zoomed(by: exp(delta * Theme.Timeline.scrollZoomRate), anchorX: Double(point.x - headerWidth)))
            return true
        }
        guard horizontal else { return false }
        board.pan(by: Double(event.scrollingDeltaX) * line)
        return true
    }

    // MARK: Keyboard

    private func handleKey(_ press: KeyPress, proxy: ScrollViewProxy, width: CGFloat) -> KeyPress.Result {
        let board = model.visionBoard
        guard board.pending == nil, board.renamingTimelineID == nil, board.prompt == nil else { return .ignored }
        if press.modifiers.contains(.command) {
            // Cmd-+ (Shift-Cmd-=) as well as the menu's Cmd-= and Cmd--.
            switch press.characters {
            case "+", "=": board.zoomIn(reduceMotion: reduceMotion)
            case "-", "_": board.zoomOut(reduceMotion: reduceMotion)
            default: return .ignored
            }
            return .handled
        }
        let option = press.modifiers.contains(.option)
        let shift = press.modifiers.contains(.shift)
        switch press.key {
        case .leftArrow, .rightArrow:
            let later = press.key == .rightArrow
            if option {
                nudgeSelected(later ? 1 : -1, resize: shift)
            } else {
                moveSelection(later ? .right : .left, proxy: proxy)
            }
            return .handled
        case .upArrow:
            moveSelection(.up, proxy: proxy)
            return .handled
        case .downArrow:
            moveSelection(.down, proxy: proxy)
            return .handled
        case .return:
            guard let id = model.selectedGoalID else { moveSelection(.right, proxy: proxy); return .handled }
            model.selectGoal(id, open: true)
            return .handled
        case .delete, .deleteForward:
            return askToDelete()
        case .escape:
            if !board.dismissTop() { model.selectedGoalID = nil }
            return .handled
        default:
            switch press.characters {
            // Backspace and forward delete as AppKit reports them.
            case "\u{7F}", "\u{08}", "\u{F728}": return askToDelete()
            case "+", "=": board.zoomIn(reduceMotion: reduceMotion)
            case "-", "_": board.zoomOut(reduceMotion: reduceMotion)
            case "t", "T": board.goToToday(reduceMotion: reduceMotion)
            default: return .ignored
            }
            return .handled
        }
    }

    private func askToDelete() -> KeyPress.Result {
        guard let id = model.selectedGoalID else { return .ignored }
        model.visionBoard.prompt = .deleteGoal(id)
        return .handled
    }

    /// Goals in the lanes that are open (collapsed lanes are skipped), for arrow-key navigation.
    private var navigationItems: [TimelineNavigation.Item] {
        let board = model.visionBoard
        return lanes.enumerated().flatMap { index, lane -> [TimelineNavigation.Item] in
            guard !board.isCollapsed(lane.id) else { return [] }
            return (goals[lane.id] ?? []).compactMap { g in g.span.map { TimelineNavigation.Item(id: g.id, lane: index, span: $0) } }
        }
    }

    private func moveSelection(_ direction: TimelineNavigation.Direction, proxy: ScrollViewProxy) {
        let items = navigationItems
        guard let next = TimelineNavigation.next(from: model.selectedGoalID, direction: direction, items: items),
              let item = items.first(where: { $0.id == next }) else { return }
        model.selectGoal(next)
        model.visionBoard.reveal(item.span, reduceMotion: reduceMotion)
        let laneID = lanes[item.lane].id
        withAnimation(reduceMotion ? nil : Theme.Motion.standard) { proxy.scrollTo(laneID) }
    }

    /// Option-arrow: moves the selected goal by the zoom level's step; with Shift, moves its end instead.
    private func nudgeSelected(_ direction: Int, resize: Bool) {
        guard let id = model.selectedGoalID, let goal = model.goal(id),
              let placed = goals[goal.timelineID]?.first(where: { $0.id == id }), let span = placed.span else { return }
        let days = direction * model.visionBoard.zoom.nudgeDays
        let cal = Calendar.current
        let dates: (start: Date?, target: Date?)
        if resize {
            guard goal.type != .milestone else { return }
            dates = TimelineDrag.datesAfterResize(shown: span, edge: .end, by: days, calendar: cal)
        } else {
            dates = TimelineDrag.datesAfterMove(type: goal.type, start: goal.startDate, target: goal.targetDate, shown: span,
                                                by: days, calendar: cal)
        }
        model.setGoalDates(goal, start: dates.start, target: dates.target)
        if let moved = TimelineDates.span(type: goal.type, start: dates.start, target: dates.target, createdAt: goal.createdAt, calendar: cal) {
            model.visionBoard.reveal(moved, reduceMotion: reduceMotion)
        }
    }
}

/// The empty corner above the lane headers.
private struct AxisCorner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack {
            Text(model.visionBoard.zoom.title.uppercased())
                .font(Theme.Fonts.label)
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.Palette.textTertiary)
            Spacer()
        }
        .padding(.horizontal, Theme.Space.l)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, Theme.Space.xs + Theme.Space.xxs)
        .accessibilityHidden(true)
    }
}

// MARK: - Axis

/// Two rows: context (years or months) on top, finer units below, with a Today tag.
struct TimelineAxisView: View {
    let axis: TimelineAxis
    let scale: TimelineScale
    let width: CGFloat

    var body: some View {
        // The renderer reads colors and fonts as it draws; reading the palette here redraws the axis on a style change.
        let _ = Theme.palette
        Canvas { ctx, size in
            let tier = Theme.Timeline.axisTier
            let pad = Theme.Space.xs + Theme.Space.xxs
            // Upper row: context labels stick to the left edge until the next one pushes them off.
            for (i, tick) in axis.major.enumerated() {
                let x = CGFloat(scale.x(tick.date))
                let next = i + 1 < axis.major.count ? CGFloat(scale.x(axis.major[i + 1].date)) : .infinity
                if x > 0, x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: 0, width: Theme.Size.hairline, height: size.height)), with: .color(Theme.Palette.subtle))
                }
                let text = ctx.resolve(Text(tick.label).font(Theme.Fonts.smallMedium).foregroundStyle(Theme.Palette.textSecondary))
                let w = text.measure(in: CGSize(width: size.width, height: tier)).width
                var lx = max(x, 0) + pad
                if lx + w + pad > next { lx = next - w - pad }
                // Pushed off by the next one: hide it rather than show a fragment.
                guard lx >= 0, lx < size.width else { continue }
                ctx.draw(text, at: CGPoint(x: lx, y: tier / 2 + Theme.Space.xxs), anchor: .leading)
            }
            // Today: a small tinted tag over the lower row, on the same line as the marker in the lanes.
            let todayX = CGFloat(scale.x(Calendar.current.startOfDay(for: Date())) + scale.pointsPerDay / 2)
            let todayLabel = ctx.resolve(Text("Today").font(Theme.Fonts.caption).foregroundStyle(Theme.Palette.accent))
            let todaySize = todayLabel.measure(in: size)
            let todayRect = CGRect(x: todayX - todaySize.width / 2 - Theme.Space.xs,
                                   y: tier + (tier - todaySize.height) / 2 - Theme.Space.xxs - Theme.Size.hairline,
                                   width: todaySize.width + Theme.Space.s, height: todaySize.height + Theme.Size.hairline * 2)
            let showToday = todayX > -Theme.Timeline.overscan && todayX < size.width + Theme.Timeline.overscan
            // Lower row: a short tick per unit, labels centered in the unit (week labels sit at the week's start).
            let centered = axis.minorUnit != .week
            for (i, tick) in axis.minor.enumerated() {
                let x = CGFloat(scale.x(tick.date))
                if x >= 0, x <= size.width {
                    ctx.fill(Path(CGRect(x: x, y: size.height - Theme.Timeline.tickMinor, width: Theme.Size.hairline, height: Theme.Timeline.tickMinor)),
                             with: .color(Theme.Palette.subtle))
                }
                guard !tick.label.isEmpty else { continue }
                let next = i + 1 < axis.minor.count ? CGFloat(scale.x(axis.minor[i + 1].date))
                    : CGFloat(scale.x(axis.minorUnit.adding(1, to: tick.date, calendar: .current) ?? tick.date))
                let text = ctx.resolve(Text(tick.label).font(Theme.Fonts.caption)
                    .foregroundStyle(tick.isWeekend ? Theme.Palette.textTertiary : Theme.Palette.textSecondary))
                let point = centered ? CGPoint(x: (x + next) / 2, y: tier + tier / 2 - Theme.Space.xxs)
                    : CGPoint(x: x + pad, y: tier + tier / 2 - Theme.Space.xxs)
                guard point.x > -Theme.Timeline.overscan, point.x < size.width + Theme.Timeline.overscan else { continue }
                let w = text.measure(in: size).width
                let labelRect = CGRect(x: centered ? point.x - w / 2 : point.x, y: todayRect.minY, width: w, height: todayRect.height)
                if showToday, labelRect.insetBy(dx: -Theme.Space.xxs, dy: 0).intersects(todayRect) { continue }
                ctx.draw(text, at: point, anchor: centered ? .center : .leading)
            }
            if showToday {
                let shape = Path(roundedRect: todayRect, cornerRadius: Theme.Radius.s)
                ctx.fill(shape, with: .color(Theme.Palette.background))
                ctx.fill(shape, with: .color(Theme.Palette.accent.opacity(Theme.Vision.Alpha.todayFill)))
                ctx.draw(todayLabel, at: CGPoint(x: todayRect.midX, y: todayRect.midY), anchor: .center)
                ctx.fill(Path(CGRect(x: todayX - Theme.Timeline.todayLine / 2, y: todayRect.maxY, width: Theme.Timeline.todayLine,
                                     height: size.height - todayRect.maxY)),
                         with: .color(Theme.Palette.accent.opacity(Theme.Vision.Alpha.todayLine)))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Dates, \(axis.major.first?.label ?? "")")
    }
}

// MARK: - Scroll wheel

/// Watches scroll-wheel events over the board without taking clicks. The handler gets the event, its position
/// (top-left origin) and whether the gesture is sideways; return true to consume it.
/// A trackpad gesture keeps the direction it started with, so a slightly diagonal swipe doesn't jitter.
struct TimelineScrollMonitor: NSViewRepresentable {
    let handler: (NSEvent, CGPoint, Bool) -> Bool

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.handler = handler
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) { view.handler = handler }

    final class MonitorView: NSView {
        var handler: ((NSEvent, CGPoint, Bool) -> Bool)?
        private var monitor: Any?
        private var lockedHorizontal: Bool?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window, let handler = self.handler else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                return handler(event, point, self.isHorizontal(event)) ? nil : event
            }
        }

        private func isHorizontal(_ e: NSEvent) -> Bool {
            if e.phase.contains(.began) || e.phase.contains(.mayBegin) { lockedHorizontal = nil }
            if let lockedHorizontal { return lockedHorizontal }
            let horizontal = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY)
            let inGesture = !e.phase.isEmpty || !e.momentumPhase.isEmpty
            if inGesture, e.scrollingDeltaX != 0 || e.scrollingDeltaY != 0 { lockedHorizontal = horizontal }
            return horizontal
        }
    }
}
