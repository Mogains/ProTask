import Foundation

/// A snapshot of the task fields that decide its calendar event.
struct EventTaskInfo {
    var title: String
    var notes: String
    var dueDate: Date?
    var hasDueTime: Bool
    var priority: Priority
    var estimateMinutes: Int?
    var isCompleted: Bool
    var topSlot: Int?
    var topDay: String?
    var recurrence: RecurrenceRule? = nil
}

struct EventSpec: Equatable {
    var title: String
    var notes: String
    var isAllDay: Bool
    var start: Date
    var end: Date
    /// Set for an open recurring task: the event repeats from this occurrence on.
    var recurrence: RecurrenceRule? = nil
}

enum EventPlanner {
    static let defaultMinutes = 30
    static let doneMark = "✓ "

    /// What the "ProTask" calendar should show for a task, or nil for no event.
    /// - Due date and time: timed event lasting the estimate (30 min default).
    /// - Due date only: all-day event on that date.
    /// - Today's Top 3 pick without a due date: all-day event today.
    /// - Completed: same event with a checkmark in front of the title.
    static func spec(for t: EventTaskInfo, today: String, calendar: Calendar = .current) -> EventSpec? {
        let pinnedToday = t.topSlot != nil && t.topDay == today
        guard t.dueDate != nil || pinnedToday else { return nil }

        var meta = ["Priority: \(t.priority.title)"]
        if let est = t.estimateMinutes { meta.append("Estimate: \(est) min") }
        if pinnedToday, let slot = t.topSlot { meta.append("Today's Top 3, #\(slot)") }
        let title = (t.isCompleted ? doneMark : "") + t.title
        // A finished occurrence keeps a single event; the open one carries the repeat.
        let repeats = t.isCompleted || t.dueDate == nil ? nil : t.recurrence
        if let r = repeats { meta.append("Repeats: \(r.summary)") }
        let notes = [t.notes.isEmpty ? nil : t.notes, meta.joined(separator: " · "), "Added by ProTask"]
            .compactMap { $0 }
            .joined(separator: "\n\n")

        if let due = t.dueDate, t.hasDueTime {
            let end = due.addingTimeInterval(Double(t.estimateMinutes ?? defaultMinutes) * 60)
            return EventSpec(title: title, notes: notes, isAllDay: false, start: due, end: end, recurrence: repeats)
        }
        let day: Date
        if let due = t.dueDate {
            day = calendar.startOfDay(for: due)
        } else {
            day = DayKey.date(from: today, calendar: calendar) ?? calendar.startOfDay(for: Date())
        }
        return EventSpec(title: title, notes: notes, isAllDay: true, start: day, end: day, recurrence: repeats)
    }
}
