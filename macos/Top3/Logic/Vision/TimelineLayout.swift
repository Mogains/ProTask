import Foundation

// MARK: - Goal mirror

/// What the timeline needs from a Goal, as a plain value (the tests build these directly).
struct TimelineGoal: Equatable, Identifiable {
    var id: UUID
    var laneID: UUID
    var title: String
    var type: GoalType
    var status: GoalStatus
    var startDate: Date?
    var targetDate: Date?
    var createdAt: Date
    /// Effective progress, 0-100.
    var progress: Int
    var sortOrder: Double = 0

    var isMilestone: Bool { type == .milestone }
}

// MARK: - Day spans

/// Whole days from `start` to `end`, both included (one-day spans have start == end). Both are start-of-day dates.
struct DaySpan: Equatable {
    var start: Date
    var end: Date

    var isSingleDay: Bool { start == end }

    /// Days covered, counting both ends.
    func days(calendar: Calendar) -> Int {
        (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
    }

    /// Where the bar ends on the track: the start of the day after `end`.
    func visualEnd(calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: end) ?? end
    }
}

enum TimelineDates {
    /// Where a goal sits on the timeline, or nil when it has no dates (it waits in its lane's undated list).
    /// - Milestones sit on one day: the target date, or the start date when there is no target.
    /// - Goals with both dates run between them (in order).
    /// - A goal with only a target runs from when it was created (or the target, if created later).
    /// - A goal with only a start date shows as that one day.
    static func span(type: GoalType, start: Date?, target: Date?, createdAt: Date, calendar: Calendar) -> DaySpan? {
        func day(_ d: Date) -> Date { calendar.startOfDay(for: d) }
        if type == .milestone {
            guard let d = target ?? start else { return nil }
            return DaySpan(start: day(d), end: day(d))
        }
        switch (start, target) {
        case let (s?, t?): return DaySpan(start: day(min(s, t)), end: day(max(s, t)))
        case let (nil, t?): return DaySpan(start: day(min(createdAt, t)), end: day(t))
        case let (s?, nil): return DaySpan(start: day(s), end: day(s))
        case (nil, nil): return nil
        }
    }

    static func span(of goal: TimelineGoal, calendar: Calendar) -> DaySpan? {
        span(type: goal.type, start: goal.startDate, target: goal.targetDate, createdAt: goal.createdAt, calendar: calendar)
    }

    /// An active goal whose last day is before today.
    static func isOverdue(status: GoalStatus, span: DaySpan?, today: Date, calendar: Calendar) -> Bool {
        guard status == .active, let span else { return false }
        return span.end < calendar.startOfDay(for: today)
    }

    /// The dates a goal added at `day` gets: goals run `days` days, milestones sit on the day.
    static func newGoalDates(type: GoalType, day: Date, days: Int, calendar: Calendar) -> (start: Date?, target: Date?) {
        let start = calendar.startOfDay(for: day)
        if type == .milestone { return (nil, start) }
        return (start, calendar.date(byAdding: .day, value: max(days, 1) - 1, to: start) ?? start)
    }
}

// MARK: - Culling

enum TimelineCulling {
    /// Only the items that overlap `interval` (half-open item ranges, so a range ending where the interval starts is out).
    /// With hundreds of goals only these get views.
    static func visible<T>(_ items: [T], in interval: DateInterval, range: (T) -> (start: Date, end: Date)?) -> [T] {
        items.filter { item in
            guard let r = range(item) else { return false }
            return r.start < interval.end && max(r.end, r.start) > interval.start
                || (r.start == r.end && interval.contains(r.start))
        }
    }

    /// The part of `x0...x1` worth drawing on a track `width` wide: off-screen parts are cut at `overscan` points past
    /// each edge, so a ten-year bar at month zoom stays a small view and its label can stay on screen.
    static func clip(_ x0: Double, _ x1: Double, width: Double, overscan: Double) -> (x0: Double, x1: Double)? {
        let lo = -overscan, hi = width + overscan
        let a = max(min(x0, x1), lo), b = min(max(x0, x1), hi)
        return a <= b ? (a, b) : nil
    }
}

// MARK: - Rows

/// Stacks a lane's goals into rows so bars and their labels never overlap.
enum TimelinePacking {
    struct Item: Equatable {
        var id: UUID
        /// Left edge of the bar or marker.
        var x0: Double
        /// Right edge including the label when it hangs outside the bar.
        var x1: Double
    }

    /// Row index per item. Greedy by left edge: each item takes the first row that is free by then.
    /// Positions are in points, so rows only change with zoom, never with panning.
    static func rows(_ items: [Item], gap: Double) -> [UUID: Int] {
        var ends: [Double] = []
        var out: [UUID: Int] = [:]
        let sorted = items.sorted { ($0.x0, $0.id.uuidString) < ($1.x0, $1.id.uuidString) }
        for item in sorted {
            if let row = ends.firstIndex(where: { $0 + gap <= item.x0 }) {
                ends[row] = max(item.x1, item.x0)
                out[item.id] = row
            } else {
                ends.append(max(item.x1, item.x0))
                out[item.id] = ends.count - 1
            }
        }
        return out
    }

    static func rowCount(_ rows: [UUID: Int]) -> Int { (rows.values.max() ?? -1) + 1 }

    /// A rough label width for packing: per-character advance plus padding (no text layout in the logic layer).
    static func estimatedLabelWidth(_ title: String, characterWidth: Double, padding: Double) -> Double {
        Double(title.count) * characterWidth + padding
    }
}

// MARK: - Dragging

/// Drag to move and drag an edge to resize, snapped to whole days.
enum TimelineDrag {
    enum Edge: Equatable { case start, end }

    /// Whole days for a horizontal drag of `translation` points.
    static func dayDelta(translation: Double, pointsPerDay: Double) -> Int {
        guard translation.isFinite, pointsPerDay > 0 else { return 0 }
        let days = (translation / pointsPerDay).rounded()
        return Int(min(max(days, -36_500), 36_500))
    }

    static func moved(_ span: DaySpan, by days: Int, calendar: Calendar) -> DaySpan {
        guard days != 0,
              let s = calendar.date(byAdding: .day, value: days, to: span.start),
              let e = calendar.date(byAdding: .day, value: days, to: span.end) else { return span }
        return DaySpan(start: calendar.startOfDay(for: s), end: calendar.startOfDay(for: e))
    }

    /// Moves one edge. The end never goes before the start, so the shortest goal is one day.
    static func resized(_ span: DaySpan, edge: Edge, by days: Int, calendar: Calendar) -> DaySpan {
        guard days != 0 else { return span }
        switch edge {
        case .start:
            guard let s = calendar.date(byAdding: .day, value: days, to: span.start) else { return span }
            return DaySpan(start: min(calendar.startOfDay(for: s), span.end), end: span.end)
        case .end:
            guard let e = calendar.date(byAdding: .day, value: days, to: span.end) else { return span }
            return DaySpan(start: span.start, end: max(calendar.startOfDay(for: e), span.start))
        }
    }

    /// The goal's dates after moving it by `days`.
    /// Milestones move their one date (and a start date if they have one). A goal shown from its creation date
    /// (target only) gets that shown start written down, so the whole bar moves rather than stretching.
    /// A goal with only a start date keeps having no target.
    static func datesAfterMove(type: GoalType, start: Date?, target: Date?, shown: DaySpan, by days: Int,
                               calendar: Calendar) -> (start: Date?, target: Date?) {
        func shift(_ d: Date?) -> Date? {
            d.flatMap { calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: $0)) }
        }
        if type == .milestone || target == nil { return (shift(start), shift(target)) }
        let span = moved(shown, by: days, calendar: calendar)
        return (span.start, span.end)
    }

    /// The goal's dates after an edge drag: both dates come from the new span.
    static func datesAfterResize(shown: DaySpan, edge: Edge, by days: Int, calendar: Calendar) -> (start: Date?, target: Date?) {
        let span = resized(shown, edge: edge, by: days, calendar: calendar)
        return (span.start, span.end)
    }
}

// MARK: - Keyboard navigation

enum TimelineNavigation {
    enum Direction: Equatable { case left, right, up, down }

    struct Item: Equatable {
        var id: UUID
        /// Position of the lane among the lanes shown (top is 0).
        var lane: Int
        var span: DaySpan
    }

    /// The goal an arrow key moves to. Left and right go through the lane in date order; up and down go to the
    /// nearest goal in the closest lane above or below that has any. With nothing selected, the first goal.
    static func next(from id: UUID?, direction: Direction, items: [Item]) -> UUID? {
        let ordered = items.sorted { ($0.lane, $0.span.start, $0.span.end, $0.id.uuidString) < ($1.lane, $1.span.start, $1.span.end, $1.id.uuidString) }
        guard let id, let current = ordered.first(where: { $0.id == id }) else { return ordered.first?.id }
        switch direction {
        case .left, .right:
            let lane = ordered.filter { $0.lane == current.lane }
            guard let i = lane.firstIndex(where: { $0.id == id }) else { return id }
            let j = direction == .left ? i - 1 : i + 1
            return lane.indices.contains(j) ? lane[j].id : id
        case .up, .down:
            let lanes = Set(ordered.map(\.lane))
            let target = direction == .up ? lanes.filter { $0 < current.lane }.max() : lanes.filter { $0 > current.lane }.min()
            guard let target else { return id }
            let center = mid(current.span)
            return ordered.filter { $0.lane == target }
                .min { abs(mid($0.span) - center) < abs(mid($1.span) - center) }?.id ?? id
        }
    }

    private static func mid(_ span: DaySpan) -> Double {
        (span.start.timeIntervalSinceReferenceDate + span.end.timeIntervalSinceReferenceDate) / 2
    }
}

// MARK: - Lane summary

/// The small summary under a lane's name, for example "3 active, 42%".
struct LaneSummary: Equatable {
    var active: Int
    var counted: Int
    /// Average progress of the lane's goals that are not dropped; nil when there are none.
    var percent: Int?
    var undated: Int

    static func make(_ goals: [TimelineGoal], calendar: Calendar) -> LaneSummary {
        let counted = goals.filter { $0.status != .dropped }
        let percent = counted.isEmpty ? nil
            : GoalProgress.clamp(Double(counted.map { GoalProgress.clamp($0.progress) }.reduce(0, +)) / Double(counted.count))
        return LaneSummary(active: goals.filter { $0.status == .active }.count, counted: counted.count, percent: percent,
                           undated: goals.filter { TimelineDates.span(of: $0, calendar: calendar) == nil }.count)
    }

    var text: String {
        guard counted > 0 else { return "No goals yet" }
        let head = active > 0 ? "\(active) active" : counted == 1 ? "1 goal" : "\(counted) goals"
        return [head, percent.map { "\($0)%" }].compactMap { $0 }.joined(separator: ", ")
    }
}

// MARK: - Lane reordering

enum LaneReorder {
    /// Where a lane dragged `offset` points (down is positive) from position `index` lands,
    /// given every lane's height in order. A lane moves once its middle passes the middle of a neighbor.
    static func targetIndex(from index: Int, offset: Double, heights: [Double]) -> Int {
        guard heights.indices.contains(index), offset.isFinite else { return max(0, min(index, heights.count - 1)) }
        var tops: [Double] = []
        var y = 0.0
        for h in heights { tops.append(y); y += h }
        let middle = tops[index] + heights[index] / 2 + offset
        var target = 0
        for (i, top) in tops.enumerated() where i != index {
            let center = top + heights[i] / 2
            if middle > center { target += 1 }
        }
        return min(max(target, 0), heights.count - 1)
    }

    /// The id to insert in front of after moving `from` to `to` (nil means the end), for VisionOrder.moving.
    static func beforeID(moving from: Int, to: Int, ids: [UUID]) -> UUID? {
        guard ids.indices.contains(from) else { return nil }
        var rest = ids
        rest.remove(at: from)
        let clamped = min(max(to, 0), rest.count)
        return clamped < rest.count ? rest[clamped] : nil
    }
}
