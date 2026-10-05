import Foundation

struct StatTask {
    var isCompleted: Bool
    var completedAt: Date?
    var dueDate: Date?
    var isPinned: Bool
    var isIdea: Bool
}

enum DailyStats {
    /// Done today divided by today's workload: done today plus open tasks that are pinned or due today or earlier.
    static func completion(_ tasks: [StatTask], today: String, resetHour: Int, calendar: Calendar = .current) -> (done: Int, total: Int, fraction: Double) {
        var done = 0, open = 0
        for t in tasks where !t.isIdea {
            if t.isCompleted {
                if let at = t.completedAt, DayKey.key(for: at, resetHour: resetHour, calendar: calendar) == today { done += 1 }
            } else if t.isPinned || (t.dueDate.map { DayKey.dateKey($0, calendar: calendar) <= today } ?? false) {
                open += 1
            }
        }
        let total = done + open
        return (done, total, total == 0 ? 0 : Double(done) / Double(total))
    }
}
