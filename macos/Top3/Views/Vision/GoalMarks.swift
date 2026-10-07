import AppKit
import SwiftUI

/// A milestone's marker.
struct Diamond: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
}

/// Drag state shared by bars and milestones: whole days moved, and which edge (nil moves the whole goal).
/// Drags measure in global space: the mark moves under the pointer as it previews, so local space would shift.
private struct MarkDrag: Equatable {
    var edge: TimelineDrag.Edge?
    var days: Int
}

// MARK: - Goal bar

/// A goal as a rounded bar: a soft tint of its timeline's hue, a tonal progress fill, and its title.
/// Drag to move, drag an edge to resize, click to open.
struct GoalBar: View {
    @Environment(AppModel.self) private var model
    let placed: PlacedGoal
    let span: DaySpan
    let color: TimelineColor
    let scale: TimelineScale
    let trackWidth: CGFloat
    let y: CGFloat

    /// Resets by itself if the gesture is cancelled, so a preview can't get stuck.
    @GestureState private var drag: MarkDrag?
    @State private var hovering = false

    var body: some View {
        let cal = Calendar.current
        let shown = previewSpan(cal)
        let (x0, x1) = TimelineMetrics.barExtent(shown, scale: scale, calendar: cal)
        let fit = drag != nil ? .full : TimelineMetrics.labelFit(barWidth: x1 - x0, goal: placed.goal)
        if let clip = TimelineCulling.clip(Double(x0), Double(x1), width: Double(trackWidth), overscan: Double(Theme.Timeline.overscan)) {
            let cx0 = CGFloat(clip.x0), cx1 = CGFloat(clip.x1)
            ZStack(alignment: .topLeading) {
                bar(width: cx1 - cx0, fullX0: x0, fullX1: x1, clipX0: cx0, fit: fit, shown: shown)
                    .offset(x: cx0)
                trailing(after: x1, inside: fit != .outside)
            }
            .offset(y: y)
        }
    }

    private var goal: TimelineGoal { placed.goal }
    private var selected: Bool { model.selectedGoalID == placed.id }

    private func previewSpan(_ cal: Calendar) -> DaySpan {
        guard let drag else { return span }
        if let edge = drag.edge { return TimelineDrag.resized(span, edge: edge, by: drag.days, calendar: cal) }
        return TimelineDrag.moved(span, by: drag.days, calendar: cal)
    }

    // MARK: Bar

    private func bar(width: CGFloat, fullX0: CGFloat, fullX1: CGFloat, clipX0: CGFloat, fit: TimelineMetrics.LabelFit,
                     shown: DaySpan) -> some View {
        let hue = Theme.Vision.color(color)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.m)
        let fraction = goal.status == .done ? 1 : Double(GoalProgress.clamp(goal.progress)) / 100
        // The fill grows from the bar's real start, even when that start is off screen.
        let fillEnd = fullX0 + (fullX1 - fullX0) * CGFloat(fraction)
        let fillWidth = min(max(fillEnd - clipX0, 0), width)
        let isIdea = goal.status == .idea
        return ZStack(alignment: .leading) {
            shape.fill(isIdea ? Theme.Palette.background : Theme.Vision.fill(color))
            if fillWidth > 0, !isIdea {
                Rectangle()
                    .fill(LinearGradient(colors: [hue.opacity(Theme.Vision.Alpha.progressLow), hue.opacity(Theme.Vision.Alpha.progressHigh)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: fillWidth)
            }
            // A bar that runs off screen keeps its title and percentage inside the visible part.
            label(fit: fit, shown: shown)
                .padding(.leading, max(-clipX0, 0))
                .padding(.trailing, max(clipX0 + width - trackWidth, 0))
        }
        .frame(width: width, height: Theme.Timeline.bar)
        .clipShape(shape)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Vision.innerHighlight)
                .frame(height: Theme.Size.hairline)
                .padding(.horizontal, Theme.Radius.m)
                .padding(.top, Theme.Size.hairline)
        }
        .overlay {
            if isIdea {
                shape.strokeBorder(hue.opacity(Theme.Vision.Alpha.borderHover),
                                   style: StrokeStyle(lineWidth: Theme.Size.hairline, dash: [Theme.Space.xs, Theme.Space.xxs]))
            } else {
                shape.strokeBorder(hue.opacity(hovering ? Theme.Vision.Alpha.borderHover : Theme.Vision.Alpha.border),
                                   lineWidth: Theme.Size.hairline)
            }
        }
        .overlay {
            if selected { shape.strokeBorder(hue, lineWidth: Theme.Timeline.selectionStroke) }
        }
        // Edges resize when there is room for them; the one being dragged stays even as the bar narrows.
        .overlay(alignment: .leading) {
            edgeHandle(.start, available: drag?.edge == .start || width >= Theme.Timeline.edgeHandle * 4 && clipX0 == fullX0)
        }
        .overlay(alignment: .trailing) {
            edgeHandle(.end, available: drag?.edge == .end || width >= Theme.Timeline.edgeHandle * 4 && clipX0 + width >= fullX1)
        }
        .opacity(goal.status == .dropped ? Theme.Opacity.past : 1)
        .contentShape(shape)
        .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
        .onTapGesture { open() }
        .gesture(dragGesture(edge: nil))
        .contextMenu { GoalMenuItems(goalID: placed.id) }
        .help("\(goal.title)\n\(VisionFormat.span(span))")
        .modifier(GoalAccessibility(placed: placed, span: span))
    }

    @ViewBuilder
    private func label(fit: TimelineMetrics.LabelFit, shown: DaySpan) -> some View {
        if drag != nil {
            Text(VisionFormat.span(shown))
                .font(Theme.Fonts.smallMedium)
                .foregroundStyle(Theme.Palette.text)
                .lineLimit(1)
                .monospacedDigit()
                .padding(.horizontal, Theme.Space.s)
        } else if fit != .outside {
            HStack(spacing: Theme.Space.xs) {
                title
                Spacer(minLength: 0)
                if fit == .full, TimelineMetrics.showsPercent(goal) {
                    Text("\(goal.progress)%")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .monospacedDigit()
                        .fixedSize()
                }
            }
            .padding(.horizontal, Theme.Space.s)
        }
    }

    private var title: some View {
        Text(goal.title)
            .font(Theme.Fonts.small)
            .foregroundStyle(goal.status == .done || goal.status == .dropped ? Theme.Palette.textSecondary : Theme.Palette.text)
            .strikethrough(goal.status == .dropped)
            .lineLimit(1)
    }

    /// The overdue dot and, when the title doesn't fit inside, the title after the bar.
    @ViewBuilder
    private func trailing(after x1: CGFloat, inside: Bool) -> some View {
        let dot = placed.overdue && drag == nil
        if dot {
            Circle().fill(Theme.Vision.overdue)
                .frame(width: Theme.Timeline.overdueDot, height: Theme.Timeline.overdueDot)
                .offset(x: x1 + Theme.Space.xs, y: (Theme.Timeline.bar - Theme.Timeline.overdueDot) / 2)
                .help("Past its target date")
                .accessibilityHidden(true)
        }
        if !inside {
            title
                .fixedSize()
                .frame(height: Theme.Timeline.bar)
                .offset(x: x1 + Theme.Space.xs + (dot ? Theme.Timeline.overdueDot + Theme.Space.xs : 0))
                .onTapGesture { open() }
                .accessibilityHidden(true)
        }
    }

    // MARK: Interaction

    @ViewBuilder
    private func edgeHandle(_ edge: TimelineDrag.Edge, available: Bool) -> some View {
        if available, goal.status != .dropped {
            Rectangle()
                .fill(Color.clear)
                .frame(width: Theme.Timeline.edgeHandle)
                .contentShape(Rectangle())
                .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                .highPriorityGesture(dragGesture(edge: edge))
                .accessibilityHidden(true)
        }
    }

    /// Moves the bar (edge nil) or one of its edges, previewing whole days as it goes.
    private func dragGesture(edge: TimelineDrag.Edge?) -> some Gesture {
        DragGesture(minimumDistance: edge == nil ? Theme.Space.xxs + Theme.Size.hairline : Theme.Size.hairline, coordinateSpace: .global)
            .updating($drag) { v, state, _ in
                state = MarkDrag(edge: edge, days: TimelineDrag.dayDelta(translation: Double(v.translation.width), pointsPerDay: scale.pointsPerDay))
            }
            .onChanged { _ in if model.selectedGoalID != placed.id { model.selectGoal(placed.id) } }
            .onEnded { v in
                commit(MarkDrag(edge: edge, days: TimelineDrag.dayDelta(translation: Double(v.translation.width), pointsPerDay: scale.pointsPerDay)))
            }
    }

    private func open() {
        model.selectGoal(placed.id, open: true)
        model.visionBoard.requestFocus()
    }

    private func commit(_ drag: MarkDrag) {
        guard drag.days != 0, let g = model.goal(placed.id) else { return }
        let cal = Calendar.current
        let dates = drag.edge.map { TimelineDrag.datesAfterResize(shown: span, edge: $0, by: drag.days, calendar: cal) }
            ?? TimelineDrag.datesAfterMove(type: g.type, start: g.startDate, target: g.targetDate, shown: span, by: drag.days, calendar: cal)
        model.setGoalDates(g, start: dates.start, target: dates.target)
        model.visionBoard.requestFocus()
    }
}

// MARK: - Milestone

/// A milestone as a small diamond on its day, with its title beside it. Drag to move, click to open.
struct MilestoneMark: View {
    @Environment(AppModel.self) private var model
    let placed: PlacedGoal
    let span: DaySpan
    let color: TimelineColor
    let scale: TimelineScale
    let trackWidth: CGFloat
    let y: CGFloat

    @GestureState private var drag: MarkDrag?
    @State private var hovering = false

    var body: some View {
        let cal = Calendar.current
        let shown = drag.map { TimelineDrag.moved(span, by: $0.days, calendar: cal) } ?? span
        let center = TimelineMetrics.milestoneCenter(shown, scale: scale)
        let size = Theme.Timeline.milestone
        let hue = Theme.Vision.color(color)
        let done = placed.goal.status == .done
        let selected = model.selectedGoalID == placed.id
        let dot = placed.overdue && drag == nil
        HStack(spacing: Theme.Space.xs) {
            ZStack {
                if selected {
                    Diamond().stroke(hue, lineWidth: Theme.Size.hairline)
                        .frame(width: size + Theme.Space.s, height: size + Theme.Space.s)
                }
                Diamond().fill(done ? hue : Theme.Palette.background)
                    .frame(width: size, height: size)
                Diamond().stroke(hue, lineWidth: Theme.Timeline.selectionStroke)
                    .frame(width: size, height: size)
            }
            .frame(width: size + Theme.Space.s, height: Theme.Timeline.bar)
            if dot {
                Circle().fill(Theme.Vision.overdue)
                    .frame(width: Theme.Timeline.overdueDot, height: Theme.Timeline.overdueDot)
                    .help("Past its date")
            }
            Text(drag != nil ? VisionFormat.span(shown) : placed.goal.title)
                .font(drag != nil ? Theme.Fonts.smallMedium : Theme.Fonts.small)
                .foregroundStyle(hovering || selected || drag != nil ? Theme.Palette.text : Theme.Palette.textSecondary)
                .strikethrough(placed.goal.status == .dropped)
                .lineLimit(1)
                .fixedSize()
        }
        .opacity(placed.goal.status == .dropped ? Theme.Opacity.past : 1)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
        .onTapGesture {
            model.selectGoal(placed.id, open: true)
            model.visionBoard.requestFocus()
        }
        .highPriorityGesture(DragGesture(minimumDistance: Theme.Space.xxs + Theme.Size.hairline, coordinateSpace: .global)
            .updating($drag) { v, state, _ in
                state = MarkDrag(edge: nil, days: TimelineDrag.dayDelta(translation: Double(v.translation.width), pointsPerDay: scale.pointsPerDay))
            }
            .onChanged { _ in if model.selectedGoalID != placed.id { model.selectGoal(placed.id) } }
            .onEnded { v in commit(days: TimelineDrag.dayDelta(translation: Double(v.translation.width), pointsPerDay: scale.pointsPerDay)) })
        .contextMenu { GoalMenuItems(goalID: placed.id) }
        .help("\(placed.goal.title)\n\(VisionFormat.span(span))")
        .modifier(GoalAccessibility(placed: placed, span: span))
        .offset(x: center - (size + Theme.Space.s) / 2, y: y)
    }

    private func commit(days: Int) {
        guard days != 0, let g = model.goal(placed.id) else { return }
        let dates = TimelineDrag.datesAfterMove(type: g.type, start: g.startDate, target: g.targetDate, shown: span, by: days,
                                                calendar: .current)
        model.setGoalDates(g, start: dates.start, target: dates.target)
        model.visionBoard.requestFocus()
    }
}

// MARK: - Shared

/// One VoiceOver element per goal, with actions for everything the mouse can do.
private struct GoalAccessibility: ViewModifier {
    @Environment(AppModel.self) private var model
    let placed: PlacedGoal
    let span: DaySpan

    func body(content: Content) -> some View {
        let g = placed.goal
        let selected = model.selectedGoalID == placed.id
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(g.title), \(g.type.title), \(g.status.title), \(g.progress) percent, \(VisionFormat.span(span))\(placed.overdue ? ", overdue" : "")")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.selectGoal(placed.id, open: true) }
            .accessibilityAction(named: "Move earlier") { nudge(-1) }
            .accessibilityAction(named: "Move later") { nudge(1) }
            .accessibilityAction(named: "Delete") { model.visionBoard.prompt = .deleteGoal(placed.id) }
    }

    private func nudge(_ direction: Int) {
        guard let goal = model.goal(placed.id) else { return }
        let dates = TimelineDrag.datesAfterMove(type: goal.type, start: goal.startDate, target: goal.targetDate, shown: span,
                                                by: direction * model.visionBoard.zoom.nudgeDays, calendar: .current)
        model.setGoalDates(goal, start: dates.start, target: dates.target)
    }
}

/// Open, status, move to another timeline, delete.
struct GoalMenuItems: View {
    @Environment(AppModel.self) private var model
    let goalID: UUID

    var body: some View {
        if let goal = model.goal(goalID) {
            Button("Open") { model.selectGoal(goalID, open: true) }
            Picker("Status", selection: Binding(get: { goal.status }, set: { model.setStatus(goal, $0) })) {
                ForEach(GoalStatus.allCases) { Text($0.title).tag($0) }
            }
            let others = model.visionTimelines().filter { $0.id != goal.timelineID }
            if !others.isEmpty {
                Menu("Move to Timeline") {
                    ForEach(others) { t in
                        Button(t.name) { model.moveGoal(goalID, to: t.id, before: nil) }
                    }
                }
            }
            Divider()
            Button("Delete Goal…") { model.visionBoard.prompt = .deleteGoal(goalID) }
        }
    }
}
