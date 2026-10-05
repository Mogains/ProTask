import Foundation

/// The fields auto sort looks at. `TaskItem` conforms; tests use a plain struct.
protocol SortableTask {
    var dueDate: Date? { get }
    var hasDueTime: Bool { get }
    var priority: Priority { get }
    var estimateMinutes: Int? { get }
    var position: Double { get }
}

enum TaskSorting {
    /// A date-only due date counts as the end of that day, so timed tasks on the same day sort first.
    static func dueKey(_ task: SortableTask, calendar: Calendar = .current) -> Date {
        guard let due = task.dueDate else { return .distantFuture }
        if task.hasDueTime { return due }
        let start = calendar.startOfDay(for: due)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? due
    }

    /// Due date (soonest first, none last), then priority (high first),
    /// then estimate (shortest first, none last), then the existing manual order.
    static func areInIncreasingOrder(_ a: SortableTask, _ b: SortableTask, calendar: Calendar = .current) -> Bool {
        let da = dueKey(a, calendar: calendar), db = dueKey(b, calendar: calendar)
        if da != db { return da < db }
        if a.priority != b.priority { return a.priority.rawValue < b.priority.rawValue }
        let ea = a.estimateMinutes ?? .max, eb = b.estimateMinutes ?? .max
        if ea != eb { return ea < eb }
        return a.position < b.position
    }

    static func sorted<T: SortableTask>(_ tasks: [T], calendar: Calendar = .current) -> [T] {
        tasks.sorted { areInIncreasingOrder($0, $1, calendar: calendar) }
    }
}
