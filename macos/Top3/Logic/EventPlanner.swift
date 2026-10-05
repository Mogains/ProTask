import CryptoKit
import Foundation

/// The kinds of calendar event a task can own.
/// - due: the due-date event of a one-off (or finished) task
/// - series: the repeating event of an open recurring task (its occurrences are the recurrence instances)
/// - pinned: an all-day event on the Top 3 day, when that isn't already the due date
enum LinkKind: String, CaseIterable, Codable {
    case due, series, pinned

    /// due and series share a slot: finishing a recurring occurrence turns its series event into a plain due event.
    var slot: LinkSlot { self == .pinned ? .pinned : .due }
}

enum LinkSlot: CaseIterable { case due, pinned }

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
    /// The task's events were deleted in Calendar; don't recreate them until it's rescheduled.
    var unscheduled: Bool = false
}

struct EventSpec: Equatable {
    var title: String
    var notes: String
    var isAllDay: Bool
    var start: Date
    var end: Date
    /// Set for an open recurring task: the event repeats from this occurrence on.
    var recurrence: RecurrenceRule? = nil
    var kind: LinkKind = .due

    /// Fingerprint of what syncs both ways (title, start, end, all-day). See EventFingerprint.
    var fingerprint: String { EventFingerprint.make(title: title, start: start, end: end, isAllDay: isAllDay) }
}

/// Equal fingerprints mean the task and the calendar agree on an event's title and time.
enum EventFingerprint {
    static func make(title: String, start: Date, end: Date, isAllDay: Bool, calendar: Calendar = .current) -> String {
        let when = isAllDay
            ? "day:\(DayKey.dateKey(start, calendar: calendar))"
            : "\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))"
        let digest = SHA256.hash(data: Data("\(title)|\(when)".utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
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
        let all = specs(for: t, today: today, calendar: calendar)
        return all[.due] ?? all[.pinned]
    }

    /// Every event a task should have, by slot:
    /// - due slot: the due-date event (a repeating series while a recurring task is open). Starred in the notes
    ///   when the task is also today's pick on its due day.
    /// - pinned slot: today's Top 3 pick gets an all-day event today, unless its due event is already today.
    /// - Unscheduled tasks (event deleted in Calendar) get none until rescheduled.
    static func specs(for t: EventTaskInfo, today: String, calendar: Calendar = .current) -> [LinkSlot: EventSpec] {
        if t.unscheduled { return [:] }
        var out: [LinkSlot: EventSpec] = [:]
        let pinnedToday = t.topSlot != nil && t.topDay == today
        let todayDate = DayKey.date(from: today, calendar: calendar) ?? calendar.startOfDay(for: Date())
        let dueOnPinDay = t.dueDate.map { calendar.isDate($0, inSameDayAs: todayDate) } ?? false
        if t.dueDate != nil, var due = dueSpec(for: t, today: today, calendar: calendar, pinned: pinnedToday && dueOnPinDay) {
            due.kind = due.recurrence != nil ? .series : .due
            out[.due] = due
        }
        if pinnedToday && !dueOnPinDay {
            var meta = ["Today's Top 3, #\(t.topSlot ?? 0)"]
            if let due = t.dueDate { meta.append("Due \(DayKey.dateKey(due, calendar: calendar))") }
            if let est = t.estimateMinutes { meta.append("Estimate: \(est) min") }
            let notes = [t.notes.isEmpty ? nil : t.notes, meta.joined(separator: " · "), "Added by ProTask"]
                .compactMap { $0 }.joined(separator: "\n\n")
            out[.pinned] = EventSpec(title: (t.isCompleted ? doneMark : "") + t.title, notes: notes, isAllDay: true,
                                     start: todayDate, end: todayDate, kind: .pinned)
        }
        return out
    }

    private static func dueSpec(for t: EventTaskInfo, today: String, calendar: Calendar, pinned: Bool) -> EventSpec? {
        let pinnedToday = pinned // due today and today's pick: noted on the due event
        guard t.dueDate != nil else { return nil }

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
