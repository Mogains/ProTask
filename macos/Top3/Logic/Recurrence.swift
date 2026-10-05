import Foundation

/// How a task repeats. Completing an occurrence creates the next one; the series is never deleted.
struct RecurrenceRule: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case daily, weekdays, weekly, monthly, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .daily: "Daily"
            case .weekdays: "Weekdays"
            case .weekly: "Weekly"
            case .monthly: "Monthly"
            case .custom: "Custom"
            }
        }
    }

    enum Unit: String, Codable, CaseIterable, Identifiable {
        case days, weeks
        var id: String { rawValue }
    }

    var kind: Kind
    /// Custom only: every N days or weeks.
    var interval: Int = 1
    var unit: Unit = .days
    /// Custom weeks only: Calendar weekday numbers (1 = Sunday ... 7 = Saturday). Empty = same weekday.
    var weekdays: [Int] = []

    static let weekdayLetters = ["S", "M", "T", "W", "T", "F", "S"]

    var summary: String {
        switch kind {
        case .daily, .weekdays, .weekly, .monthly: return kind.title
        case .custom:
            let n = max(interval, 1)
            let unitText = unit == .days ? (n == 1 ? "day" : "\(n) days") : (n == 1 ? "week" : "\(n) weeks")
            var s = "Every \(unitText)"
            if unit == .weeks, !weekdays.isEmpty {
                let names = Calendar.current.shortWeekdaySymbols
                s += " on " + weekdays.sorted().map { names[$0 - 1] }.joined(separator: ", ")
            }
            return s
        }
    }

    /// The occurrence right after `date`, keeping its time of day.
    func next(after date: Date, calendar: Calendar = .current) -> Date {
        func add(_ c: Calendar.Component, _ n: Int, _ d: Date) -> Date { calendar.date(byAdding: c, value: n, to: d) ?? d }
        let n = max(interval, 1)
        switch kind {
        case .daily:
            return add(.day, 1, date)
        case .weekdays:
            var d = add(.day, 1, date)
            while calendar.isDateInWeekend(d) { d = add(.day, 1, d) }
            return d
        case .weekly:
            return add(.day, 7, date)
        case .monthly:
            return add(.month, 1, date)
        case .custom where unit == .days:
            return add(.day, n, date)
        case .custom:
            let days = Set(weekdays.filter { (1...7).contains($0) })
            guard !days.isEmpty else { return add(.day, 7 * n, date) }
            let wd = calendar.component(.weekday, from: date)
            // Later in the same (Sunday-based) week?
            for offset in 1...(7 - wd) where days.contains(wd + offset) { return add(.day, offset, date) }
            // Otherwise the first chosen day of the week N weeks on.
            let blockStart = add(.day, (7 - wd + 1) + 7 * (n - 1), date)
            for offset in 0..<7 {
                let d = add(.day, offset, blockStart)
                if days.contains(calendar.component(.weekday, from: d)) { return d }
            }
            return blockStart
        }
    }

    /// The next occurrence after `due` that isn't before `today`, so a late completion doesn't create overdue tasks.
    func nextOccurrence(after due: Date, today: Date, calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: today)
        var d = next(after: due, calendar: calendar)
        var guardCount = 0
        while d < startOfToday && guardCount < 1000 {
            d = next(after: d, calendar: calendar)
            guardCount += 1
        }
        return d
    }

    // MARK: Storage

    var encoded: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    init(kind: Kind, interval: Int = 1, unit: Unit = .days, weekdays: [Int] = []) {
        self.kind = kind
        self.interval = interval
        self.unit = unit
        self.weekdays = weekdays
    }

    init?(encoded: String?) {
        guard let data = encoded?.data(using: .utf8), let rule = try? JSONDecoder().decode(RecurrenceRule.self, from: data) else { return nil }
        self = rule
    }
}
