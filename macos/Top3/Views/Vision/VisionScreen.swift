import SwiftData
import SwiftUI

// MARK: - Board data

/// A lane as the board draws it.
struct LaneInfo: Identifiable, Equatable {
    let id: UUID
    let name: String
    let color: TimelineColor
    let archived: Bool
    let summary: LaneSummary
}

/// A goal with where it sits on the timeline, worked out once per data change rather than per frame.
struct PlacedGoal: Identifiable, Equatable {
    let goal: TimelineGoal
    /// Nil for goals without dates.
    let span: DaySpan?
    /// The start of the day after the span: where the bar ends.
    let visualEnd: Date?
    let overdue: Bool

    var id: UUID { goal.id }
}

// MARK: - Screen

/// Vision: long-range goals on timeline lanes. Private to this Mac.
struct VisionScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Every task (not narrowed by the tag filter), for progress from linked tasks.
    let tasks: [TaskItem]
    @Query(sort: \VisionTimeline.sortOrder) private var timelines: [VisionTimeline]
    @Query(sort: \Goal.sortOrder) private var goals: [Goal]

    var body: some View {
        @Bindable var board = model.visionBoard
        let data = boardData
        Group {
            if timelines.isEmpty {
                VisionEmptyState()
            } else {
                HStack(spacing: 0) {
                    TimelineBoard(lanes: data.lanes, goals: data.goals, archivedCount: data.archivedCount)
                    if let id = board.openGoalID, let goal = goals.first(where: { $0.id == id }) {
                        let linked = data.linked[id] ?? (0, 0)
                        HStack(spacing: 0) {
                            Hairline(vertical: true)
                            GoalDetailPanel(goal: goal, progress: data.progress[id] ?? goal.progress,
                                            linkedDone: linked.done, linkedTotal: linked.total)
                                .id(goal.id)
                                .frame(width: Theme.GoalPanel.width)
                        }
                        .frame(maxHeight: .infinity)
                        .background(Theme.Palette.surface)
                        // Slides in from the right; with Reduce Motion it fades instead.
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? Theme.Motion.standard : Theme.Motion.list, value: board.openGoalID != nil)
                .overlay {
                    if let request = board.viewer {
                        GoalImageViewer(request: request).transition(.opacity)
                    }
                }
                .animation(Theme.Motion.standard, value: board.viewer)
            }
        }
        .sheet(item: $board.prompt) { prompt in
            VisionPromptSheet(prompt: prompt).presentationBackground(Theme.Palette.surface)
        }
    }

    private struct BoardData {
        var lanes: [LaneInfo]
        var goals: [UUID: [PlacedGoal]]
        var progress: [UUID: Int]
        var linked: [UUID: (done: Int, total: Int)]
        var archivedCount: Int
    }

    /// Plain values for the board: lanes in order (archived ones only when shown), each lane's goals placed.
    private var boardData: BoardData {
        let cal = Calendar.current
        let now = Date()
        var linked: [UUID: (done: Int, total: Int)] = [:]
        for t in tasks {
            guard let id = t.goalID else { continue }
            var c = linked[id] ?? (0, 0)
            c.total += 1
            if t.isCompleted { c.done += 1 }
            linked[id] = c
        }
        var byLane: [UUID: [PlacedGoal]] = [:]
        var progress: [UUID: Int] = [:]
        for g in goals {
            let counts = linked[g.id] ?? (0, 0)
            let p = GoalProgress.effective(mode: g.progressMode, manual: g.progress, status: g.status, metric: g.metric,
                                           linkedDone: counts.done, linkedTotal: counts.total)
            progress[g.id] = p
            let value = TimelineGoal(id: g.id, laneID: g.timelineID, title: g.title, type: g.type, status: g.status,
                                     startDate: g.startDate, targetDate: g.targetDate, createdAt: g.createdAt,
                                     progress: p, sortOrder: g.sortOrder)
            let span = TimelineDates.span(of: value, calendar: cal)
            byLane[g.timelineID, default: []].append(PlacedGoal(
                goal: value, span: span, visualEnd: span?.visualEnd(calendar: cal),
                overdue: TimelineDates.isOverdue(status: g.status, span: span, today: now, calendar: cal)))
        }
        let showArchived = model.visionBoard.showArchived
        let lanes = timelines.filter { showArchived || !$0.archived }.map { t in
            LaneInfo(id: t.id, name: t.name, color: t.color, archived: t.archived,
                     summary: LaneSummary.make((byLane[t.id] ?? []).map(\.goal), calendar: cal))
        }
        return BoardData(lanes: lanes, goals: byLane, progress: progress, linked: linked, archivedCount: timelines.filter(\.archived).count)
    }
}

// MARK: - Empty state

/// No timelines yet: a short explanation and one button per template.
struct VisionEmptyState: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionLabel(title: "Vision")
                Text("Lay out the years ahead.")
                    .font(Theme.font(Theme.TextSize.input, .medium))
                    .foregroundStyle(Theme.Palette.text)
                Text("Each timeline is a lane for one part of your life. Put long-range goals and milestones on it, then zoom from a decade down to a month. Everything here stays on this Mac.")
                    .font(Theme.Fonts.small)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SectionLabel(title: "Start a timeline")
                FlowButtons()
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.xl)
        .frame(maxWidth: Theme.Size.contentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private struct FlowButtons: View {
        @Environment(AppModel.self) private var model
        var body: some View {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.xxs) { buttons }
                VStack(alignment: .leading, spacing: Theme.Space.xxs) { buttons }
            }
        }

        @ViewBuilder private var buttons: some View {
            Button {
                if let t = model.createBlankTimeline() { model.visionBoard.renamingTimelineID = t.id }
            } label: {
                HStack(spacing: Theme.Space.xs) {
                    Icon(.add, size: Theme.Size.dragHandle)
                    Text("Blank")
                }
            }
            .buttonStyle(.ghost)
            .help("A new empty timeline you can name")
            ForEach(TimelineTemplate.all) { template in
                Button { model.createTimeline(from: template) } label: {
                    HStack(spacing: Theme.Space.xs) {
                        Circle().fill(Theme.Vision.color(template.color))
                            .frame(width: Theme.Timeline.laneDot, height: Theme.Timeline.laneDot)
                        Text(template.name)
                    }
                }
                .buttonStyle(.ghost)
                .help(template.details)
                .accessibilityLabel("New \(template.name) timeline")
            }
        }
    }
}

// MARK: - Header controls

/// Vision's header accessory: zoom levels, Today, and New timeline.
struct VisionHeaderControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A query rather than a fetch: this view redraws on every zoom frame to show the level.
    @Query private var timelines: [VisionTimeline]

    var body: some View {
        if timelines.isEmpty {
            NewTimelineMenu()
        } else {
            controls
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.s) {
                Segments(options: TimelineZoom.allCases, selection: zoomBinding) { $0.title }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Zoom")
                    .help("Zoom (⌘= and ⌘-, or pinch)")
                todayButton
                NewTimelineMenu()
            }
            HStack(spacing: Theme.Space.s) {
                PopUpMenuButton(help: "Zoom (⌘= and ⌘-, or pinch)") {
                    TimelineZoom.allCases.map { level in
                        .item(level.title, checked: level == model.visionBoard.zoom) {
                            model.visionBoard.setZoom(level, reduceMotion: reduceMotion)
                        }
                    }
                } label: {
                    HStack(spacing: Theme.Space.xs) {
                        Text(model.visionBoard.zoom.title).font(Theme.Fonts.small)
                        Icon(.chevronDown, size: Theme.Size.dragHandle)
                    }
                    .foregroundStyle(Theme.Palette.textSecondary)
                }
                .accessibilityLabel("Zoom: \(model.visionBoard.zoom.title)")
                todayButton
                NewTimelineMenu(compact: true)
            }
        }
    }

    private var todayButton: some View {
        Button("Today") { model.visionBoard.goToToday(reduceMotion: reduceMotion) }
            .buttonStyle(.ghost)
            .help("Go to today (⌘T)")
    }

    private var zoomBinding: Binding<TimelineZoom> {
        Binding(get: { model.visionBoard.zoom },
                set: { model.visionBoard.setZoom($0, reduceMotion: reduceMotion) })
    }
}

/// "New timeline": blank, or one of the templates (templates only add the lane).
struct NewTimelineMenu: View {
    @Environment(AppModel.self) private var model
    var compact = false

    var body: some View {
        PopUpMenuButton(help: "New timeline: blank or from a template") {
            [.item("Blank Timeline") {
                if let t = model.createBlankTimeline() { model.visionBoard.renamingTimelineID = t.id }
            }, .separator, .header("From a template")]
                + TimelineTemplate.all.map { template in .item(template.name) { model.createTimeline(from: template) } }
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Icon(.add, size: Theme.Size.dragHandle)
                if !compact { Text("New timeline").font(Theme.Fonts.small) }
            }
            .foregroundStyle(Theme.Palette.textSecondary)
        }
        .accessibilityLabel("New timeline")
    }
}
