import AppKit
import SwiftUI

/// One timeline: its header on the left, its goals on the track.
struct TimelineLaneRow: View {
    @Environment(AppModel.self) private var model
    let lane: LaneInfo
    let index: Int
    let laneCount: Int
    let goals: [PlacedGoal]
    let layout: TimelineMetrics.LaneLayout
    let scale: TimelineScale
    let axis: TimelineAxis
    let trackWidth: CGFloat
    let onReorderDrag: (CGFloat) -> Void
    let onReorderEnd: (CGFloat) -> Void

    var body: some View {
        let collapsed = model.visionBoard.isCollapsed(lane.id)
        HStack(spacing: 0) {
            LaneHeader(lane: lane, index: index, laneCount: laneCount, collapsed: collapsed,
                       undated: goals.filter { $0.span == nil }, trackWidth: trackWidth,
                       onReorderDrag: onReorderDrag, onReorderEnd: onReorderEnd)
                .frame(width: Theme.Timeline.laneHeaderWidth, height: layout.height, alignment: .topLeading)
            Hairline(vertical: true)
            LaneTrack(lane: lane, goals: goals, layout: layout, scale: scale, axis: axis, width: trackWidth, collapsed: collapsed)
        }
        .frame(height: layout.height)
        .opacity(lane.archived ? Theme.Opacity.past : 1)
    }
}

// MARK: - Header

private struct LaneHeader: View {
    @Environment(AppModel.self) private var model
    let lane: LaneInfo
    let index: Int
    let laneCount: Int
    let collapsed: Bool
    let undated: [PlacedGoal]
    let trackWidth: CGFloat
    let onReorderDrag: (CGFloat) -> Void
    let onReorderEnd: (CGFloat) -> Void

    @State private var hovering = false
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private var renaming: Bool { model.visionBoard.renamingTimelineID == lane.id }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.xs) {
            IconButton(icon: collapsed ? .chevronRight : .chevronDown,
                       help: collapsed ? "Expand \(lane.name)" : "Collapse \(lane.name)") {
                model.visionBoard.toggleCollapsed(lane.id)
            }
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HStack(spacing: Theme.Space.s) {
                    Circle().fill(Theme.Vision.color(lane.color))
                        .frame(width: Theme.Timeline.laneDot, height: Theme.Timeline.laneDot)
                    if renaming { nameField } else {
                        Text(lane.name)
                            .font(Theme.Fonts.bodyMedium)
                            .foregroundStyle(Theme.Palette.text)
                            .lineLimit(1)
                    }
                }
                .frame(height: Theme.Size.iconButton)
                .padding(.trailing, Theme.Size.iconButton)
                if !collapsed {
                    summary.padding(.leading, Theme.Timeline.laneDot + Theme.Space.s)
                }
            }
            Spacer(minLength: 0)
        }
        // Floats over the header so the summary keeps the full width; shown on hover, always reachable by keyboard.
        .overlay(alignment: .topTrailing) {
            PopUpMenuButton(help: "Timeline actions", padded: false) { menuChoices } label: {
                Icon(.more)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: Theme.Size.iconButton, height: Theme.Size.iconButton)
            }
            .opacity(hovering || renaming ? 1 : 0)
            .accessibilityLabel("Actions for \(lane.name)")
        }
        .padding(.leading, Theme.Space.s)
        .padding(.trailing, Theme.Space.xs)
        .padding(.top, collapsed ? (Theme.Timeline.laneCollapsed - Theme.Size.iconButton) / 2
                 : Theme.Timeline.lanePadding + (Theme.Timeline.laneRow - Theme.Size.iconButton) / 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.Vision.color(lane.color).opacity(Theme.Vision.Alpha.laneEdge))
                .frame(width: Theme.Timeline.laneEdge)
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
        .gesture(DragGesture(minimumDistance: Theme.Space.xs, coordinateSpace: .global)
            .onChanged { v in onReorderDrag(v.translation.height) }
            .onEnded { v in onReorderEnd(v.translation.height) })
        .contextMenu { LaneMenuItems(lane: lane, index: index, laneCount: laneCount) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(lane.name) timeline, \(lane.summary.text)\(lane.archived ? ", archived" : "")")
        .accessibilityAction(named: collapsed ? "Expand" : "Collapse") { model.visionBoard.toggleCollapsed(lane.id) }
        .accessibilityAction(named: "Rename") { model.visionBoard.renamingTimelineID = lane.id }
        .help("Drag to reorder. Right-click for more.")
    }

    /// The "..." menu: the same actions as the right-click menu.
    private var menuChoices: [MenuChoice] {
        let board = model.visionBoard
        let recolor: [MenuChoice] = TimelineColor.allCases.map { color in
            .item(color.title, checked: color == lane.color) {
                guard let t = model.visionTimeline(lane.id) else { return }
                model.updateTimeline(t, with: TimelineDraft(name: t.name, details: t.details, color: color))
            }
        }
        return [.item("Rename") { board.renamingTimelineID = lane.id }, .separator, .header("Color")] + recolor + [
            .separator,
            .item("Move Up", enabled: index > 0) { model.moveTimelineAmongShown(lane.id, by: -1) },
            .item("Move Down", enabled: index < laneCount - 1) { model.moveTimelineAmongShown(lane.id, by: 1) },
            .item(collapsed ? "Expand" : "Collapse") { board.toggleCollapsed(lane.id) },
            .separator,
            .item(lane.archived ? "Unarchive" : "Archive") {
                if let t = model.visionTimeline(lane.id) { model.setArchived(t, !lane.archived) }
            },
            .item("Delete Timeline…") { board.prompt = .deleteTimeline(lane.id) },
        ]
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.s) {
                Text(lane.summary.text)
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                if let percent = lane.summary.percent {
                    LaneProgress(color: lane.color, fraction: Double(percent) / 100)
                }
            }
            if lane.archived {
                Text("Archived")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            if !undated.isEmpty {
                PopUpMenuButton(help: "Goals without dates. Pick one to place it in view.", padded: false) {
                    [.header("Place on the timeline")] + undated.map { g in .item(g.goal.title) { place(g) } }
                } label: {
                    Text(undated.count == 1 ? "1 undated" : "\(undated.count) undated")
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .underline(pattern: .dot, color: Theme.Palette.border)
                }
                .accessibilityLabel(undated.count == 1 ? "1 undated goal" : "\(undated.count) undated goals")
            }
        }
    }

    private var nameField: some View {
        TextField("", text: $name, prompt: Text("Timeline name").foregroundStyle(Theme.Palette.textTertiary))
            .textFieldStyle(.plain)
            .font(Theme.Fonts.bodyMedium)
            .foregroundStyle(Theme.Palette.text)
            .focused($nameFocused)
            .focusEffectDisabled()
            .onAppear {
                name = lane.name
                DispatchQueue.main.async { nameFocused = true }
            }
            .onSubmit(commitRename)
            .onExitCommand {
                model.visionBoard.renamingTimelineID = nil
                model.visionBoard.requestFocus()
            }
            .onChange(of: nameFocused) { if !nameFocused, renaming { commitRename() } }
    }

    private func commitRename() {
        if let t = model.visionTimeline(lane.id), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.updateTimeline(t, with: TimelineDraft(name: name, details: t.details, color: t.color))
        }
        model.visionBoard.renamingTimelineID = nil
        model.visionBoard.requestFocus()
    }

    /// Gives an undated goal dates around the middle of the view and selects it.
    private func place(_ g: PlacedGoal) {
        guard let goal = model.goal(g.id) else { return }
        let board = model.visionBoard
        let day = board.scale.date(atX: Double(trackWidth) / 2)
        let dates = TimelineDates.newGoalDates(type: goal.type, day: day, days: board.zoom.newGoalDays, calendar: .current)
        model.setGoalDates(goal, start: dates.start, target: dates.target)
        model.selectGoal(goal.id)
        board.requestFocus()
    }
}

/// Rename, recolor, reorder, collapse, archive and delete: the lane's context menu and its "..." menu.
private struct LaneMenuItems: View {
    @Environment(AppModel.self) private var model
    let lane: LaneInfo
    let index: Int
    let laneCount: Int

    var body: some View {
        Button("Rename") { model.visionBoard.renamingTimelineID = lane.id }
        Picker("Color", selection: colorBinding) {
            ForEach(TimelineColor.allCases) { Text($0.title).tag($0) }
        }
        Divider()
        Button("Move Up") { model.moveTimelineAmongShown(lane.id, by: -1) }.disabled(index == 0)
        Button("Move Down") { model.moveTimelineAmongShown(lane.id, by: 1) }.disabled(index >= laneCount - 1)
        Button(model.visionBoard.isCollapsed(lane.id) ? "Expand" : "Collapse") { model.visionBoard.toggleCollapsed(lane.id) }
        Divider()
        Button(lane.archived ? "Unarchive" : "Archive") {
            if let t = model.visionTimeline(lane.id) { model.setArchived(t, !lane.archived) }
        }
        Button("Delete Timeline…") { model.visionBoard.prompt = .deleteTimeline(lane.id) }
    }

    private var colorBinding: Binding<TimelineColor> {
        Binding(get: { lane.color }, set: { color in
            guard let t = model.visionTimeline(lane.id) else { return }
            model.updateTimeline(t, with: TimelineDraft(name: t.name, details: t.details, color: color))
        })
    }
}

/// The lane's progress at a glance: a short track with a tonal fill of the lane's hue.
private struct LaneProgress: View {
    let color: TimelineColor
    let fraction: Double

    var body: some View {
        let hue = Theme.Vision.color(color)
        ZStack(alignment: .leading) {
            Capsule().fill(Theme.Vision.fill(color))
            Capsule()
                .fill(LinearGradient(colors: [hue.opacity(Theme.Vision.Alpha.progressHigh), hue],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: Theme.Timeline.laneProgressWidth * min(max(fraction, 0), 1))
        }
        .frame(width: Theme.Timeline.laneProgressWidth, height: Theme.Size.indicator + Theme.Size.hairline)
        .accessibilityHidden(true)
    }
}

// MARK: - Track

private struct LaneTrack: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let lane: LaneInfo
    let goals: [PlacedGoal]
    let layout: TimelineMetrics.LaneLayout
    let scale: TimelineScale
    let axis: TimelineAxis
    let width: CGFloat
    let collapsed: Bool

    var body: some View {
        let window = scale.visibleInterval(width: Double(width), margin: Double(Theme.Timeline.cullMargin))
        let visible = TimelineCulling.visible(goals, in: window) { g in
            guard let span = g.span, let end = g.visualEnd else { return nil }
            return (span.start, end)
        }
        ZStack(alignment: .topLeading) {
            LaneGrid(axis: axis, scale: scale)
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(panGesture)
                .onTapGesture(count: 2) { p in addGoal(at: p) }
                .onTapGesture { tapEmpty() }
            if collapsed {
                CollapsedMarks(goals: visible, color: lane.color, scale: scale, width: width)
                    .allowsHitTesting(false)
            } else {
                ForEach(visible) { g in
                    if let span = g.span, let row = layout.rows[g.id] {
                        if g.goal.isMilestone {
                            MilestoneMark(placed: g, span: span, color: lane.color, scale: scale, trackWidth: width,
                                          y: TimelineMetrics.barY(row: row))
                        } else {
                            GoalBar(placed: g, span: span, color: lane.color, scale: scale, trackWidth: width,
                                    y: TimelineMetrics.barY(row: row))
                        }
                    }
                }
                if let pending = model.visionBoard.pending, pending.laneID == lane.id, let row = layout.promptRow {
                    let x = CGFloat(scale.x(pending.day))
                    InlineGoalPrompt(lane: lane)
                        .offset(x: min(max(x, Theme.Space.xs), max(width - Theme.Timeline.promptWidth - Theme.Space.xs, Theme.Space.xs)),
                                y: TimelineMetrics.barY(row: row) - (Theme.Size.iconButton - Theme.Timeline.bar) / 2)
                }
            }
        }
        .frame(width: width, height: layout.height, alignment: .topLeading)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(lane.name) goals")
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: Theme.Space.xxs)
            .onChanged { v in
                let board = model.visionBoard
                if board.gestureStart == nil { board.gestureStart = board.scale }
                if let start = board.gestureStart { board.setScale(start.panned(by: Double(v.translation.width))) }
            }
            .onEnded { _ in model.visionBoard.gestureStart = nil }
    }

    private func tapEmpty() {
        let board = model.visionBoard
        if collapsed {
            board.toggleCollapsed(lane.id)
            return
        }
        if board.pending != nil { board.pending = nil }
        model.selectGoal(nil)
        board.requestFocus()
    }

    /// Double-click on empty space: an inline title field at that day; the goal exists once it has a title.
    private func addGoal(at point: CGPoint) {
        let board = model.visionBoard
        if collapsed { board.toggleCollapsed(lane.id) }
        let day = Calendar.current.startOfDay(for: scale.date(atX: Double(point.x)))
        board.pending = PendingGoal(laneID: lane.id, day: day)
    }
}

/// Unit lines, weekends at day zoom, a faint wash over the past, and today's line.
private struct LaneGrid: View {
    let axis: TimelineAxis
    let scale: TimelineScale

    var body: some View {
        Canvas { ctx, size in
            let todayStart = Calendar.current.startOfDay(for: Date())
            let todayX = CGFloat(scale.x(todayStart))
            if todayX > 0 {
                ctx.fill(Path(CGRect(x: 0, y: 0, width: min(todayX, size.width), height: size.height)), with: .color(Theme.Vision.past))
            }
            if axis.minorUnit == .day {
                let w = CGFloat(scale.pointsPerDay)
                for tick in axis.minor where tick.isWeekend {
                    ctx.fill(Path(CGRect(x: CGFloat(scale.x(tick.date)), y: 0, width: w, height: size.height)), with: .color(Theme.Vision.weekend))
                }
            }
            for tick in axis.minor {
                let x = CGFloat(scale.x(tick.date))
                guard x >= 0, x <= size.width else { continue }
                ctx.fill(Path(CGRect(x: x, y: 0, width: Theme.Size.hairline, height: size.height)), with: .color(Theme.Vision.gridMinor))
            }
            for tick in axis.major {
                let x = CGFloat(scale.x(tick.date))
                guard x >= 0, x <= size.width else { continue }
                ctx.fill(Path(CGRect(x: x, y: 0, width: Theme.Size.hairline, height: size.height)), with: .color(Theme.Palette.border))
            }
            let center = todayX + CGFloat(scale.pointsPerDay) / 2
            if center >= 0, center <= size.width {
                ctx.fill(Path(CGRect(x: center - Theme.Timeline.todayLine / 2, y: 0, width: Theme.Timeline.todayLine, height: size.height)),
                         with: .color(Theme.Palette.accent.opacity(Theme.Vision.Alpha.todayLine)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A collapsed lane: thin bars and small diamonds on one line, no labels.
private struct CollapsedMarks: View {
    let goals: [PlacedGoal]
    let color: TimelineColor
    let scale: TimelineScale
    let width: CGFloat

    var body: some View {
        let hue = Theme.Vision.color(color)
        Canvas { ctx, size in
            let cal = Calendar.current
            let mid = size.height / 2
            for g in goals {
                guard let span = g.span else { continue }
                let faded = g.goal.status == .dropped || g.goal.status == .idea
                let shade = hue.opacity(faded ? Theme.Vision.Alpha.progressLow : Theme.Vision.Alpha.laneEdge)
                if g.goal.isMilestone {
                    let c = TimelineMetrics.milestoneCenter(span, scale: scale)
                    let r = Theme.Timeline.collapsedMilestone / 2
                    ctx.fill(Diamond().path(in: CGRect(x: c - r, y: mid - r, width: r * 2, height: r * 2)), with: .color(shade))
                } else {
                    let (x0, x1) = TimelineMetrics.barExtent(span, scale: scale, calendar: cal)
                    guard let clip = TimelineCulling.clip(Double(x0), Double(x1), width: Double(width), overscan: Double(Theme.Timeline.overscan)) else { continue }
                    let h = Theme.Timeline.collapsedBar
                    ctx.fill(Path(roundedRect: CGRect(x: clip.x0, y: Double(mid - h / 2), width: clip.x1 - clip.x0, height: Double(h)),
                                  cornerRadius: h / 2), with: .color(shade))
                }
            }
        }
    }
}

// MARK: - Inline title field

/// Appears where you double-clicked. Return adds the goal (or milestone); Esc, or leaving it empty, cancels.
private struct InlineGoalPrompt: View {
    @Environment(AppModel.self) private var model
    let lane: LaneInfo
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        let type = model.visionBoard.pending?.type ?? .goal
        HStack(spacing: Theme.Space.xs) {
            TextField("", text: $title, prompt: Text(type == .milestone ? "Milestone title" : "Goal title")
                .foregroundStyle(Theme.Palette.textTertiary))
                .textFieldStyle(.plain)
                .font(Theme.Fonts.small)
                .foregroundStyle(Theme.Palette.text)
                .focused($focused)
                .focusEffectDisabled()
                .onSubmit(create)
                .onExitCommand(perform: cancel)
            Button(type == .milestone ? "Milestone" : "Goal") {
                model.visionBoard.pending?.type = type == .milestone ? .goal : .milestone
                focused = true
            }
            .buttonStyle(.ghost)
            .help("Switch between a goal and a milestone")
        }
        .padding(.leading, Theme.Space.s)
        .frame(width: Theme.Timeline.promptWidth, height: Theme.Size.iconButton)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.elevated))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m)
            .strokeBorder(Theme.Vision.color(lane.color), style: StrokeStyle(lineWidth: Theme.Size.hairline, dash: [Theme.Space.xs, Theme.Space.xxs])))
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: focused) { if !focused, title.trimmingCharacters(in: .whitespaces).isEmpty { cancel() } }
    }

    private func create() {
        let board = model.visionBoard
        guard let pending = board.pending else { return }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return cancel() }
        let dates = TimelineDates.newGoalDates(type: pending.type, day: pending.day, days: board.zoom.newGoalDays, calendar: .current)
        let goal = model.createGoal(GoalDraft(title: title, timelineID: lane.id, type: pending.type, status: .planned,
                                              startDate: dates.start, targetDate: dates.target))
        board.pending = nil
        if let goal { model.selectGoal(goal.id) }
        board.requestFocus()
    }

    private func cancel() {
        model.visionBoard.pending = nil
        model.visionBoard.requestFocus()
    }
}
