import Foundation

/// A compact plain-text copy of your day for pasting into an AI chat. Built only when you ask,
/// copied to the clipboard, never sent anywhere by ProTask and never logged.
enum ChatSnapshot {
    struct Item: Equatable {
        var title: String
        var notes: String = ""
        var dueDate: Date?
        var hasDueTime = false
        var priority: Priority = .medium
        var estimateMinutes: Int?
        var isCompleted = false
        var waitingOn: String = ""
        var followUpDate: Date?
    }

    struct Event: Equatable {
        var title: String
        var start: Date
        var end: Date
        var isAllDay: Bool
    }

    struct Input: Equatable {
        var today: Date
        var top3: [Int: Item] = [:]
        var haveTo: [Item] = []
        var niceTo: [Item] = []
        var waiting: [Item] = []
        var ideas: [Item] = []
        var events: [Event] = []
    }

    /// Which parts are included. Each has a toggle in Settings.
    struct Sections: Equatable {
        var top3 = true
        var lists = true
        var waiting = true
        var ideas = true
        var events = true
        var notes = true
    }

    static let noteLimit = 80
    static let titleLimit = 200

    /// The protask-actions format the reply should end with (parsed by ChatActions).
    static let actionsFooter = """
    If you suggest changes, end your reply with one fenced code block labeled protask-actions, one action per line:
    ```protask-actions
    add | Have to do | email prof | due 2026-10-09 15:00
    move | task title | Nice to do
    top3 | 1 | task title
    due | task title | 2026-10-09 15:00
    ```
    Only these four actions exist. Lists are Have to do, Nice to do, Waiting On and Parking Lot. Use exact task titles from above, dates as YYYY-MM-DD and optional 24-hour times.
    """

    static func build(_ input: Input, sections: Sections, prompt: ChatPrompt? = nil, calendar: Calendar = .current) -> String {
        var out: [String] = ["ProTask snapshot for \(dayLabel(input.today, calendar: calendar))"]
        let line = { (i: Item) in itemLine(i, today: input.today, notes: sections.notes, calendar: calendar) }

        if sections.top3 {
            var block = ["Top 3 today:"]
            for n in 1...3 {
                if let i = input.top3[n] {
                    block.append("\(n). " + (i.isCompleted ? "[done] " : "") + line(i))
                } else {
                    block.append("\(n). (empty)")
                }
            }
            out.append(block.joined(separator: "\n"))
        }
        if sections.lists {
            out.append(list("Have to do", input.haveTo.map(line)))
            out.append(list("Nice to do", input.niceTo.map(line)))
        }
        if sections.waiting, !input.waiting.isEmpty {
            out.append(list("Waiting On", input.waiting.map { i in
                var parts = [clean(i.title, limit: titleLimit)]
                if !i.waitingOn.isEmpty { parts.append("waiting on \(clean(i.waitingOn, limit: 60))") }
                if let f = i.followUpDate { parts.append("follow up \(DayKey.dateKey(f, calendar: calendar))") }
                return parts.joined(separator: ", ")
            }))
        }
        if sections.ideas {
            out.append(list("Parking Lot", input.ideas.map { clean($0.title, limit: titleLimit) }))
        }
        if sections.events {
            out.append(list("Today's calendar", input.events.map { e in
                let when = e.isAllDay ? "all day" : "\(time(e.start, calendar)) to \(time(e.end, calendar))"
                return "\(when) \(clean(e.title, limit: titleLimit))"
            }))
        }
        if let prompt { out.append(prompt.instruction) }
        out.append(actionsFooter)
        return out.joined(separator: "\n\n")
    }

    // MARK: Formatting

    private static func list(_ title: String, _ lines: [String]) -> String {
        ([title + ":"] + (lines.isEmpty ? ["(none)"] : lines.map { "- " + $0 })).joined(separator: "\n")
    }

    private static func itemLine(_ i: Item, today: Date, notes: Bool, calendar: Calendar) -> String {
        var meta: [String] = []
        if let due = i.dueDate {
            meta.append("due " + DayKey.dateKey(due, calendar: calendar) + (i.hasDueTime ? " " + time(due, calendar) : ""))
        }
        if i.priority != .medium { meta.append(i.priority == .high ? "high priority" : "low priority") }
        if let est = i.estimateMinutes { meta.append("\(est) min") }
        var s = clean(i.title, limit: titleLimit)
        if !meta.isEmpty { s += " (" + meta.joined(separator: ", ") + ")" }
        if notes, !i.notes.isEmpty { s += ". Notes: " + clean(i.notes, limit: noteLimit) }
        return s
    }

    /// One line, trimmed, and cut at `limit` characters with an ellipsis.
    static func clean(_ s: String, limit: Int) -> String {
        let one = s.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        return one.count > limit ? String(one.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…" : one
    }

    private static func time(_ d: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private static func dayLabel(_ d: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE"
        return "\(f.string(from: d)) \(DayKey.dateKey(d, calendar: calendar))"
    }
}

/// One-tap requests above the chat. Each copies the snapshot plus a short instruction.
enum ChatPrompt: String, CaseIterable, Identifiable {
    case planDay, pickTop3, sortParkingLot, dropThisWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .planDay: "Plan my day"
        case .pickTop3: "Pick my Top 3"
        case .sortParkingLot: "Sort my Parking Lot"
        case .dropThisWeek: "What should I drop this week"
        }
    }

    var instruction: String {
        switch self {
        case .planDay:
            "Plan my day: put my Top 3 and today's tasks around my calendar events, with rough times. Keep it short."
        case .pickTop3:
            "Pick my Top 3 for today from these tasks and say in one line each why. Use top3 actions for your picks."
        case .sortParkingLot:
            "Sort my Parking Lot: for each idea, say whether it belongs in Have to do, Nice to do, or should stay parked. Use move actions."
        case .dropThisWeek:
            "What should I drop or postpone this week to make room for what matters? Be direct and brief."
        }
    }
}
