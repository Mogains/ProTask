import Foundation

/// A measurable goal: from `start` to `target`, now at `current`, in `unit`.
/// Targets can go down as well as up (weight, debt, a 10k time).
struct GoalMetric: Equatable, Codable {
    var name: String
    var start: Double
    var current: Double
    var target: Double
    var unit: String = ""

    var isDecreasing: Bool { target < start }
    /// How far along, 0...1.
    var fraction: Double { GoalProgress.metricFraction(start: start, current: current, target: target) }
    var percent: Int { GoalProgress.percent(fraction) }
    var isReached: Bool { fraction >= 1 }
    /// Still to go, in the metric's unit (0 once the target is reached or passed).
    var remaining: Double { isReached ? 0 : abs(target - current) }
    var isValid: Bool { start.isFinite && current.isFinite && target.isFinite }
}

/// Progress math for goals. Progress is always a whole number from 0 to 100.
enum GoalProgress {
    static let range = 0...100

    static func clamp(_ value: Int) -> Int { min(max(value, range.lowerBound), range.upperBound) }

    /// Rounds to the nearest whole percent; NaN counts as 0.
    static func clamp(_ value: Double) -> Int {
        guard !value.isNaN else { return 0 }
        if value >= Double(range.upperBound) { return range.upperBound }
        if value <= Double(range.lowerBound) { return range.lowerBound }
        return Int(value.rounded())
    }

    static func percent(_ fraction: Double) -> Int { clamp(fraction * 100) }

    /// How far `current` has moved from `start` toward `target`, as 0...1.
    /// Works whichever way the target lies: passing it counts as done, moving away from it counts as 0.
    /// A target equal to the start is done when `current` is on it.
    static func metricFraction(start: Double, current: Double, target: Double) -> Double {
        guard start.isFinite, current.isFinite, target.isFinite else { return 0 }
        let span = target - start
        if span == 0 { return current == target ? 1 : 0 }
        return min(max((current - start) / span, 0), 1)
    }

    /// The progress a goal shows.
    /// - Done goals show 100.
    /// - Manual: the number that was set.
    /// - Automatic: the metric if there is one, otherwise the share of linked items (tasks, later routines) that are done,
    ///   otherwise the number that was set, so switching modes never jumps to zero.
    static func effective(mode: ProgressMode, manual: Int, status: GoalStatus, metric: GoalMetric?,
                          linkedDone: Int = 0, linkedTotal: Int = 0) -> Int {
        if status == .done { return range.upperBound }
        guard mode == .auto else { return clamp(manual) }
        if let metric, metric.isValid { return metric.percent }
        if linkedTotal > 0 { return percent(Double(min(max(linkedDone, 0), linkedTotal)) / Double(linkedTotal)) }
        return clamp(manual)
    }
}
