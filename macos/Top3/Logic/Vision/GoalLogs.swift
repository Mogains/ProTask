import Foundation

/// A goal log entry as plain values (mirrors GoalLog).
struct GoalLogEntry: Identifiable, Equatable {
    let id: UUID
    var date: Date
    var createdAt: Date
    var text: String
    var metricValue: Double?
    var progress: Int?
}

/// Ordering and rules for a goal's update log.
enum GoalLogOrder {
    /// Newest day first; on the same day, the most recently written first.
    static func newestFirst(_ entries: [GoalLogEntry], calendar: Calendar = .current) -> [GoalLogEntry] {
        entries.sorted { a, b in
            let da = calendar.startOfDay(for: a.date), db = calendar.startOfDay(for: b.date)
            if da != db { return da > db }
            if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            return a.id.uuidString > b.id.uuidString
        }
    }

    /// An entry needs words or a number.
    static func isValid(text: String, metricValue: Double?) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (metricValue?.isFinite ?? false)
    }

    /// A newly logged value becomes the metric's current value unless an entry for a later day already has a value.
    static func updatesCurrent(entryDate: Date, otherValueDates: [Date], calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: entryDate)
        return otherValueDates.allSatisfy { calendar.startOfDay(for: $0) <= day }
    }
}

// MARK: - Metric series

/// One point of a metric's history.
struct MetricPoint: Equatable, Identifiable {
    enum Kind: Equatable { case start, logged, current }
    let date: Date
    let value: Double
    let kind: Kind

    var id: Date { date }
}

/// The points for a goal's metric graph: the starting value, every day a value was logged, and today's value.
enum MetricSeries {
    /// - The start value sits on the goal's start day (or the day it was made), when that is before every logged day.
    /// - Several values on one day keep the one written last.
    /// - The current value is added for today when it differs from the last point and nothing is logged for today or later.
    static func points(metric: GoalMetric, startDate: Date?, createdAt: Date, logs: [GoalLogEntry], today: Date,
                       calendar: Calendar = .current) -> [MetricPoint] {
        var byDay: [Date: GoalLogEntry] = [:]
        for log in logs {
            guard let v = log.metricValue, v.isFinite else { continue }
            let day = calendar.startOfDay(for: log.date)
            if let existing = byDay[day], existing.createdAt > log.createdAt { continue }
            byDay[day] = log
        }
        var points = byDay.keys.sorted().compactMap { day in
            byDay[day]?.metricValue.map { MetricPoint(date: day, value: $0, kind: .logged) }
        }
        let todayDay = calendar.startOfDay(for: today)
        let startDay = calendar.startOfDay(for: startDate ?? createdAt)
        if metric.start.isFinite, startDay < (points.first?.date ?? todayDay) {
            points.insert(MetricPoint(date: startDay, value: metric.start, kind: .start), at: 0)
        }
        if metric.current.isFinite {
            if let last = points.last {
                if last.date < todayDay, last.value != metric.current {
                    points.append(MetricPoint(date: todayDay, value: metric.current, kind: .current))
                }
            } else {
                points.append(MetricPoint(date: todayDay, value: metric.current, kind: .current))
            }
        }
        return points
    }

    /// The value range to draw: every point and the target, with a little room above and below.
    static func valueDomain(_ points: [MetricPoint], target: Double, padding: Double = 0.12) -> ClosedRange<Double> {
        let values = points.map(\.value).filter(\.isFinite) + (target.isFinite ? [target] : [])
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let span = hi - lo
        let pad = span > 0 ? span * padding : max(abs(hi) * padding, 1)
        return (lo - pad)...(hi + pad)
    }
}
