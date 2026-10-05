import Foundation

/// "YYYY-MM-DD" keys for days. The app's day rolls over at a configurable hour (default 4am),
/// so working past midnight still counts as the same day.
enum DayKey {
    static let defaultResetHour = 4

    static func key(for date: Date = Date(), resetHour: Int = defaultResetHour, calendar: Calendar = .current) -> String {
        dateKey(date.addingTimeInterval(-Double(resetHour) * 3600), calendar: calendar)
    }

    /// Plain calendar date of `date`, no reset-hour shift.
    static func dateKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func adding(_ days: Int, to key: String, calendar: Calendar = .current) -> String {
        guard let d = date(from: key, calendar: calendar),
              let shifted = calendar.date(byAdding: .day, value: days, to: d) else { return key }
        return dateKey(shifted, calendar: calendar)
    }

    /// Consecutive completed days ending today, or yesterday if today isn't complete yet.
    static func streak(completeDays: Set<String>, today: String, calendar: Calendar = .current) -> Int {
        var day = completeDays.contains(today) ? today : adding(-1, to: today, calendar: calendar)
        var count = 0
        while completeDays.contains(day) {
            count += 1
            day = adding(-1, to: day, calendar: calendar)
        }
        return count
    }
}
