import XCTest

final class RecurrenceTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    private func d(_ m: Int, _ day: Int, _ h: Int = 9) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: day, hour: h))!
    }
    private func key(_ date: Date) -> String { DayKey.dateKey(date, calendar: cal) }

    func testDailyKeepsTimeOfDay() {
        let next = RecurrenceRule(kind: .daily).next(after: d(10, 5, 15), calendar: cal)
        XCTAssertEqual(key(next), "2026-10-06")
        XCTAssertEqual(cal.component(.hour, from: next), 15)
    }

    func testWeekdaysSkipWeekend() {
        // Friday Oct 9 -> Monday Oct 12
        XCTAssertEqual(key(RecurrenceRule(kind: .weekdays).next(after: d(10, 9), calendar: cal)), "2026-10-12")
        XCTAssertEqual(key(RecurrenceRule(kind: .weekdays).next(after: d(10, 6), calendar: cal)), "2026-10-07")
    }

    func testWeeklyAndMonthly() {
        XCTAssertEqual(key(RecurrenceRule(kind: .weekly).next(after: d(10, 5), calendar: cal)), "2026-10-12")
        XCTAssertEqual(key(RecurrenceRule(kind: .monthly).next(after: d(10, 5), calendar: cal)), "2026-11-05")
        XCTAssertEqual(key(RecurrenceRule(kind: .monthly).next(after: d(1, 31), calendar: cal)), "2026-02-28")
    }

    func testCustomEveryNDays() {
        XCTAssertEqual(key(RecurrenceRule(kind: .custom, interval: 3, unit: .days).next(after: d(10, 5), calendar: cal)), "2026-10-08")
    }

    func testCustomEveryTwoWeeksOnMondayAndThursday() {
        let rule = RecurrenceRule(kind: .custom, interval: 2, unit: .weeks, weekdays: [2, 5])
        // Mon Oct 5 -> Thu Oct 8 (same week)
        XCTAssertEqual(key(rule.next(after: d(10, 5), calendar: cal)), "2026-10-08")
        // Thu Oct 8 -> Mon Oct 19 (two weeks on)
        XCTAssertEqual(key(rule.next(after: d(10, 8), calendar: cal)), "2026-10-19")
    }

    func testCustomWeeksWithoutDaysUsesSameWeekday() {
        let rule = RecurrenceRule(kind: .custom, interval: 2, unit: .weeks)
        XCTAssertEqual(key(rule.next(after: d(10, 5), calendar: cal)), "2026-10-19")
    }

    func testLateCompletionSkipsMissedOccurrences() {
        // Daily task due Oct 1, completed Oct 5: next is Oct 5, not Oct 2.
        let next = RecurrenceRule(kind: .daily).nextOccurrence(after: d(10, 1), today: d(10, 5, 18), calendar: cal)
        XCTAssertEqual(key(next), "2026-10-05")
        // On time: next is simply the following day.
        XCTAssertEqual(key(RecurrenceRule(kind: .daily).nextOccurrence(after: d(10, 5), today: d(10, 5, 18), calendar: cal)), "2026-10-06")
    }

    func testEncodingRoundTrip() {
        let rule = RecurrenceRule(kind: .custom, interval: 2, unit: .weeks, weekdays: [2, 4])
        XCTAssertEqual(RecurrenceRule(encoded: rule.encoded), rule)
        XCTAssertNil(RecurrenceRule(encoded: nil))
        XCTAssertNil(RecurrenceRule(encoded: "garbage"))
    }

    func testSummary() {
        XCTAssertEqual(RecurrenceRule(kind: .weekdays).summary, "Weekdays")
        XCTAssertEqual(RecurrenceRule(kind: .custom, interval: 3, unit: .days).summary, "Every 3 days")
    }
}
