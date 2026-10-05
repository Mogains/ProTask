import Foundation

/// Plain numbers for the weekly review. Pure, so it can be tested.
enum WeeklyStats {
    struct Input {
        var completedAt: [Date]
        /// Due dates of tasks still open.
        var openDue: [Date]
        var focusSessions: [(start: Date, seconds: Int)]
        /// (estimate minutes, actual seconds) for tasks completed this week with both set.
        var estimateVsActual: [(estimate: Int, actualSeconds: Int)]
        var completeTop3Days: Set<String>
    }

    struct Result: Equatable {
        var completedThisWeek: Int
        var completedLastWeek: Int
        /// 0...1, nil when nothing was due or done.
        var completionRate: Double?
        var focusSeconds: Int
        /// actual / estimated, nil without data.
        var actualToEstimate: Double?
        var fullTop3Days: Int
        /// Completions per day, first day of the week first.
        var perDay: [Int]
    }

    static func weekInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 86_400)
    }

    static func compute(_ input: Input, now: Date, calendar: Calendar = .current) -> Result {
        let week = weekInterval(containing: now, calendar: calendar)
        let lastWeek = DateInterval(start: calendar.date(byAdding: .day, value: -7, to: week.start)!, end: week.start)
        func inWeek(_ d: Date) -> Bool { d >= week.start && d < week.end }

        let done = input.completedAt.filter(inWeek)
        let last = input.completedAt.filter { $0 >= lastWeek.start && $0 < lastWeek.end }
        let openDueThisWeek = input.openDue.filter { $0 < week.end }.count
        let denominator = done.count + openDueThisWeek

        let est = input.estimateVsActual.reduce(0) { $0 + $1.estimate * 60 }
        let act = input.estimateVsActual.reduce(0) { $0 + $1.actualSeconds }

        var perDay = Array(repeating: 0, count: 7)
        for d in done {
            let i = calendar.dateComponents([.day], from: week.start, to: calendar.startOfDay(for: d)).day ?? 0
            if (0..<7).contains(i) { perDay[i] += 1 }
        }

        var fullDays = 0
        for i in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: i, to: week.start),
               input.completeTop3Days.contains(DayKey.dateKey(day, calendar: calendar)) { fullDays += 1 }
        }

        return Result(
            completedThisWeek: done.count,
            completedLastWeek: last.count,
            completionRate: denominator == 0 ? nil : Double(done.count) / Double(denominator),
            focusSeconds: input.focusSessions.filter { inWeek($0.start) }.reduce(0) { $0 + $1.seconds },
            actualToEstimate: est == 0 ? nil : Double(act) / Double(est),
            fullTop3Days: fullDays,
            perDay: perDay
        )
    }
}
