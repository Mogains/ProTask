import Foundation

// MARK: - Zoom levels

/// The four named zoom levels of the Vision timeline. Pinching zooms smoothly between them;
/// the level shown in the header is the nearest one.
enum TimelineZoom: String, CaseIterable, Identifiable, Codable {
    case decade, year, quarter, month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .decade: "Decade"
        case .year: "Year"
        case .quarter: "Quarter"
        case .month: "Month"
        }
    }

    /// Horizontal points per day: about ten years, one year, one quarter or one month across a 730pt track.
    var pointsPerDay: Double {
        switch self {
        case .decade: 0.2
        case .year: 2
        case .quarter: 8
        case .month: 28
        }
    }

    /// How long a goal added by double-clicking lasts, in days, so it is easy to see and grab at this level.
    var newGoalDays: Int {
        switch self {
        case .decade: 365
        case .year: 90
        case .quarter: 30
        case .month: 7
        }
    }

    /// How far one keyboard nudge moves a goal, in days.
    var nudgeDays: Int {
        switch self {
        case .decade: 30
        case .year: 7
        case .quarter, .month: 1
        }
    }

    /// Pinch and scroll limits: about 25 years across down to under a week across.
    static let minPointsPerDay = 0.08
    static let maxPointsPerDay = 80.0
    /// Each Cmd+= or Cmd+- step past the named levels.
    static let stepFactor = 1.5

    static func clamp(_ ppd: Double) -> Double {
        guard ppd.isFinite, ppd > 0 else { return TimelineZoom.year.pointsPerDay }
        return min(max(ppd, minPointsPerDay), maxPointsPerDay)
    }

    /// The named level closest to `ppd`, measured on a log scale.
    static func nearest(to ppd: Double) -> TimelineZoom {
        let p = log(clamp(ppd))
        return allCases.min { abs(log($0.pointsPerDay) - p) < abs(log($1.pointsPerDay) - p) } ?? .year
    }

    /// The next level in (Cmd+=): the next named level, or a fixed step past the last one.
    static func zoomedIn(from ppd: Double) -> Double {
        let current = clamp(ppd)
        if let next = allCases.map(\.pointsPerDay).sorted().first(where: { $0 > current * 1.001 }) { return next }
        return clamp(current * stepFactor)
    }

    /// The next level out (Cmd+-): the previous named level, or a fixed step past the first one.
    static func zoomedOut(from ppd: Double) -> Double {
        let current = clamp(ppd)
        if let next = allCases.map(\.pointsPerDay).sorted(by: >).first(where: { $0 < current / 1.001 }) { return next }
        return clamp(current / stepFactor)
    }
}

// MARK: - Scale

/// Maps dates to horizontal positions on the timeline track and back.
/// `origin` is the date at x = 0 (the left edge of the track). Time runs at a constant `pointsPerDay`.
struct TimelineScale: Equatable {
    static let secondsPerDay: Double = 86_400

    var origin: Date
    var pointsPerDay: Double

    init(origin: Date, pointsPerDay: Double) {
        self.origin = origin
        self.pointsPerDay = TimelineZoom.clamp(pointsPerDay)
    }

    var pointsPerSecond: Double { pointsPerDay / Self.secondsPerDay }
    var zoom: TimelineZoom { TimelineZoom.nearest(to: pointsPerDay) }

    func x(_ date: Date) -> Double { date.timeIntervalSince(origin) * pointsPerSecond }

    func date(atX x: Double) -> Date { origin.addingTimeInterval(x / pointsPerSecond) }

    /// The dates across a track `width` points wide, widened by `margin` points on both sides.
    func visibleInterval(width: Double, margin: Double = 0) -> DateInterval {
        let start = date(atX: -margin)
        let end = date(atX: max(width, 0) + margin)
        return DateInterval(start: start, end: max(end, start))
    }

    /// Content moved `dx` points to the right (drag or scroll): the dates shift left by the same amount.
    func panned(by dx: Double) -> TimelineScale {
        guard dx.isFinite else { return self }
        return TimelineScale(origin: date(atX: -dx), pointsPerDay: pointsPerDay)
    }

    /// Zooms to `ppd` (clamped) keeping the date under `anchorX` in place.
    func zoomed(to ppd: Double, anchorX: Double) -> TimelineScale {
        let anchor = date(atX: anchorX)
        let p = TimelineZoom.clamp(ppd)
        return TimelineScale(origin: anchor.addingTimeInterval(-anchorX / (p / Self.secondsPerDay)), pointsPerDay: p)
    }

    func zoomed(by factor: Double, anchorX: Double) -> TimelineScale {
        guard factor.isFinite, factor > 0 else { return self }
        return zoomed(to: pointsPerDay * factor, anchorX: anchorX)
    }

    /// A scale at `ppd` that puts `date` at `fraction` of the track's width (0 left edge, 1 right edge).
    static func placing(_ date: Date, atFraction fraction: Double, width: Double, pointsPerDay ppd: Double) -> TimelineScale {
        let p = TimelineZoom.clamp(ppd)
        let x = max(width, 0) * min(max(fraction, 0), 1)
        return TimelineScale(origin: date.addingTimeInterval(-x / (p / secondsPerDay)), pointsPerDay: p)
    }

    /// The smallest pan that brings `start...end` into view with `padding` points to spare.
    /// Too wide to fit: its start goes to the left edge (plus padding).
    func revealing(start: Date, end: Date, width: Double, padding: Double) -> TimelineScale {
        let x0 = x(start), x1 = x(max(end, start))
        let left = padding, right = max(width - padding, left)
        if x1 - x0 > right - left || x0 < left { return panned(by: left - x0) }
        if x1 > right { return panned(by: right - x1) }
        return self
    }

    /// Keeps the visible dates within `bounds` (when the bounds are wider than the view).
    func clamped(to bounds: DateInterval, width: Double) -> TimelineScale {
        let visible = visibleInterval(width: width)
        if visible.duration >= bounds.duration { return self }
        if visible.start < bounds.start { return TimelineScale(origin: bounds.start, pointsPerDay: pointsPerDay) }
        if visible.end > bounds.end { return TimelineScale(origin: bounds.end.addingTimeInterval(-visible.duration), pointsPerDay: pointsPerDay) }
        return self
    }

    /// One frame of an animated change from `a` to `b`. Zoom eases on a log scale and the date under
    /// `anchorX` slides from where it was to where it ends up, so a zoom around the pointer keeps that date still.
    static func interpolate(from a: TimelineScale, to b: TimelineScale, anchorX: Double, progress t: Double) -> TimelineScale {
        let t = min(max(t, 0), 1)
        if t <= 0 { return a }
        if t >= 1 { return b }
        let ppd = exp(log(a.pointsPerDay) + (log(b.pointsPerDay) - log(a.pointsPerDay)) * t)
        let from = a.date(atX: anchorX).timeIntervalSinceReferenceDate
        let to = b.date(atX: anchorX).timeIntervalSinceReferenceDate
        let anchor = Date(timeIntervalSinceReferenceDate: from + (to - from) * t)
        return TimelineScale(origin: anchor.addingTimeInterval(-anchorX / (ppd / secondsPerDay)), pointsPerDay: ppd)
    }

    /// Ease-out cubic: quick start, gentle stop, no overshoot.
    static func easeOut(_ t: Double) -> Double {
        let c = min(max(t, 0), 1)
        return 1 - pow(1 - c, 3)
    }
}
