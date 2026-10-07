import Foundation

/// A calendar unit the timeline axis can mark.
enum TimelineAxisUnit: Equatable, CaseIterable {
    case day, week, month, quarter, year, decade

    /// Rough length in days, used only to decide what fits.
    var approximateDays: Double {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30.44
        case .quarter: 91.31
        case .year: 365.25
        case .decade: 3652.5
        }
    }

    /// The unit that frames this one in the axis's upper row.
    var context: TimelineAxisUnit {
        switch self {
        case .day, .week: .month
        case .month, .quarter: .year
        case .year, .decade: .decade
        }
    }

    /// The first instant of the unit that contains `date`.
    func start(of date: Date, calendar: Calendar) -> Date {
        switch self {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        case .quarter:
            let month = TimelineAxisUnit.month.start(of: date, calendar: calendar)
            let offset = (calendar.component(.month, from: month) - 1) % 3
            return calendar.date(byAdding: .month, value: -offset, to: month) ?? month
        case .year:
            return calendar.dateInterval(of: .year, for: date)?.start ?? calendar.startOfDay(for: date)
        case .decade:
            let year = TimelineAxisUnit.year.start(of: date, calendar: calendar)
            let offset = ((calendar.component(.year, from: year) % 10) + 10) % 10
            return calendar.date(byAdding: .year, value: -offset, to: year) ?? year
        }
    }

    /// `date` moved forward by `count` of this unit.
    func adding(_ count: Int, to date: Date, calendar: Calendar) -> Date? {
        switch self {
        case .day: calendar.date(byAdding: .day, value: count, to: date)
        case .week: calendar.date(byAdding: .day, value: 7 * count, to: date)
        case .month: calendar.date(byAdding: .month, value: count, to: date)
        case .quarter: calendar.date(byAdding: .month, value: 3 * count, to: date)
        case .year: calendar.date(byAdding: .year, value: count, to: date)
        case .decade: calendar.date(byAdding: .year, value: 10 * count, to: date)
        }
    }
}

/// One mark on the axis: a unit boundary and its label (empty when skipped to keep labels apart).
struct TimelineTick: Equatable {
    var date: Date
    var label: String
    /// Saturday or Sunday; only set on day ticks, which shade weekends faintly.
    var isWeekend = false
}

/// The two-row axis above the lanes: context on top (years, months), finer units below.
///
/// - Decade zoom: decades over years.
/// - Year zoom: years over months.
/// - Quarter zoom: months over weeks.
/// - Month zoom: months over days.
struct TimelineAxis: Equatable {
    var majorUnit: TimelineAxisUnit
    var minorUnit: TimelineAxisUnit
    var major: [TimelineTick]
    var minor: [TimelineTick]

    /// The finest unit used must be at least this wide.
    static let minimumUnitWidth: Double = 28
    /// Labels closer than this skip some ticks (years only: 2, 5 or 10 at a time).
    static let minimumLabelSpacing: Double = 32
    /// Safety cap on ticks per row.
    static let maximumTicks = 4000

    static func minorUnit(forPointsPerDay ppd: Double) -> TimelineAxisUnit {
        [TimelineAxisUnit.day, .week, .month, .quarter, .year].first { $0.approximateDays * ppd >= minimumUnitWidth } ?? .year
    }

    static func make(for interval: DateInterval, pointsPerDay ppd: Double, calendar: Calendar) -> TimelineAxis {
        let minorUnit = minorUnit(forPointsPerDay: ppd)
        let majorUnit = minorUnit.context
        let yearStride = [1, 2, 5, 10].first { Double($0) * TimelineAxisUnit.year.approximateDays * ppd >= minimumLabelSpacing } ?? 10
        let minor = ticks(minorUnit, in: interval, calendar: calendar) { date in
            label(minorUnit, date, calendar: calendar, isMinor: true, yearStride: yearStride)
        }
        let major = ticks(majorUnit, in: interval, calendar: calendar) { date in
            label(majorUnit, date, calendar: calendar, isMinor: false, yearStride: 1)
        }
        return TimelineAxis(majorUnit: majorUnit, minorUnit: minorUnit, major: major, minor: minor)
    }

    /// Every boundary of `unit` from the one at or before `interval.start` to the last before `interval.end`.
    /// The first tick can sit left of the interval so its label can stick to the left edge.
    static func ticks(_ unit: TimelineAxisUnit, in interval: DateInterval, calendar: Calendar,
                      label: (Date) -> String) -> [TimelineTick] {
        var out: [TimelineTick] = []
        var date = unit.start(of: interval.start, calendar: calendar)
        while date < interval.end || out.isEmpty, out.count < maximumTicks {
            out.append(TimelineTick(date: date, label: label(date),
                                    isWeekend: unit == .day && calendar.isDateInWeekend(date)))
            guard let next = unit.adding(1, to: date, calendar: calendar), next > date else { break }
            date = next
        }
        return out
    }

    static func label(_ unit: TimelineAxisUnit, _ date: Date, calendar: Calendar, isMinor: Bool, yearStride: Int) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let year = c.year ?? 0, month = c.month ?? 1, day = c.day ?? 1
        switch unit {
        case .day, .week:
            return String(day)
        case .month:
            let symbols = isMinor ? calendar.shortMonthSymbols : calendar.monthSymbols
            let name = symbols.indices.contains(month - 1) ? symbols[month - 1] : String(month)
            return isMinor ? name : "\(name) \(year)"
        case .quarter:
            return "Q\((month - 1) / 3 + 1)"
        case .year:
            return year % max(yearStride, 1) == 0 ? String(year) : ""
        case .decade:
            return "\(year)s"
        }
    }
}
