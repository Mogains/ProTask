import XCTest

final class DayKeyTests: XCTestCase {
    private let cal = Calendar.current
    private func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))! }

    func testDayRollsOverAtResetHour() {
        XCTAssertEqual(DayKey.key(for: at(6, 3, 59), resetHour: 4, calendar: cal), "2026-10-05")
        XCTAssertEqual(DayKey.key(for: at(6, 4), resetHour: 4, calendar: cal), "2026-10-06")
        XCTAssertEqual(DayKey.key(for: at(6, 0, 30), resetHour: 0, calendar: cal), "2026-10-06")
    }

    func testAddingDaysCrossesMonths() {
        XCTAssertEqual(DayKey.adding(1, to: "2026-10-31", calendar: cal), "2026-11-01")
        XCTAssertEqual(DayKey.adding(-1, to: "2026-03-01", calendar: cal), "2026-02-28")
    }

    func testStreak() {
        let days: Set = ["2026-10-02", "2026-10-03", "2026-10-04"]
        XCTAssertEqual(DayKey.streak(completeDays: days, today: "2026-10-05", calendar: cal), 3, "today unfinished still counts yesterday")
        XCTAssertEqual(DayKey.streak(completeDays: days.union(["2026-10-05"]), today: "2026-10-05", calendar: cal), 4)
        XCTAssertEqual(DayKey.streak(completeDays: days, today: "2026-10-06", calendar: cal), 0)
    }
}

final class FreeTimeTests: XCTestCase {
    private let cal = Calendar.current
    private func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: h, minute: m))! }

    func testGapsBetweenOverlappingEvents() {
        let busy = [DateInterval(start: at(9), end: at(10)), DateInterval(start: at(9, 30), end: at(11)), DateInterval(start: at(13), end: at(14))]
        let gaps = FreeTime.gaps(busy: busy, dayStart: at(8), dayEnd: at(18), now: at(7))
        XCTAssertEqual(gaps.map { cal.component(.hour, from: $0.start) }, [8, 11, 14])
        XCTAssertEqual(gaps.map { cal.component(.hour, from: $0.end) }, [9, 13, 18])
    }

    func testStartsAtNowAndDropsTinyGaps() {
        let gaps = FreeTime.gaps(busy: [DateInterval(start: at(12, 10), end: at(15))], dayStart: at(8), dayEnd: at(18), now: at(12))
        XCTAssertEqual(gaps.map { Int($0.duration / 60) }, [180])
    }
}

final class EventPlannerTests: XCTestCase {
    private let cal = Calendar.current
    private let today = "2026-10-05"
    private func info(_ f: (inout EventTaskInfo) -> Void = { _ in }) -> EventTaskInfo {
        var i = EventTaskInfo(title: "Write report", notes: "", dueDate: nil, hasDueTime: false, priority: .medium,
                              estimateMinutes: nil, isCompleted: false, topSlot: nil, topDay: nil)
        f(&i)
        return i
    }

    func testNoEventWithoutDueDateOrTodaysPin() {
        XCTAssertNil(EventPlanner.spec(for: info(), today: today, calendar: cal))
        XCTAssertNil(EventPlanner.spec(for: info { $0.topSlot = 1; $0.topDay = "2026-10-04" }, today: today, calendar: cal))
    }

    func testTodaysPickBecomesAllDayToday() {
        let s = EventPlanner.spec(for: info { $0.topSlot = 2; $0.topDay = today }, today: today, calendar: cal)!
        XCTAssertTrue(s.isAllDay)
        XCTAssertEqual(DayKey.dateKey(s.start, calendar: cal), today)
        XCTAssertEqual(s.title, "Write report")
    }

    func testTimedEventUsesEstimate() {
        let due = cal.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 14))!
        let s = EventPlanner.spec(for: info { $0.dueDate = due; $0.hasDueTime = true; $0.estimateMinutes = 45 }, today: today, calendar: cal)!
        XCTAssertFalse(s.isAllDay)
        XCTAssertEqual(s.start, due)
        XCTAssertEqual(s.end.timeIntervalSince(due), 45 * 60)
        let noEstimate = EventPlanner.spec(for: info { $0.dueDate = due; $0.hasDueTime = true }, today: today, calendar: cal)!
        XCTAssertEqual(noEstimate.end.timeIntervalSince(due), 30 * 60)
    }

    func testCompletedGetsCheckmark() {
        let s = EventPlanner.spec(for: info { $0.dueDate = Date(); $0.isCompleted = true }, today: today, calendar: cal)!
        XCTAssertEqual(s.title, "✓ Write report")
    }
}
