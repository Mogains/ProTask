import XCTest

final class WeeklyStatsTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        return c
    }()
    private func d(_ day: Int, _ h: Int = 12) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h))! }

    func testCountsRatesAndSparkline() {
        // Week of Mon Oct 5 – Sun Oct 11; "now" is Wed Oct 7.
        let input = WeeklyStats.Input(
            completedAt: [d(5), d(5), d(7), d(1), d(2)],
            openDue: [d(6), d(20)],
            focusSessions: [(d(5), 1500), (d(6), 3000), (d(1), 600)],
            estimateVsActual: [(30, 2400), (60, 3600)],
            completeTop3Days: ["2026-10-05", "2026-10-06", "2026-09-30"]
        )
        let r = WeeklyStats.compute(input, now: d(7), calendar: cal)
        XCTAssertEqual(r.completedThisWeek, 3)
        XCTAssertEqual(r.completedLastWeek, 2)
        XCTAssertEqual(r.completionRate!, 3.0 / 4.0, accuracy: 0.001) // one open task due this week
        XCTAssertEqual(r.focusSeconds, 4500)
        XCTAssertEqual(r.actualToEstimate!, 6000.0 / 5400.0, accuracy: 0.001)
        XCTAssertEqual(r.fullTop3Days, 2)
        XCTAssertEqual(r.perDay, [2, 0, 1, 0, 0, 0, 0])
    }

    func testEmptyWeekHasNoRates() {
        let r = WeeklyStats.compute(.init(completedAt: [], openDue: [], focusSessions: [], estimateVsActual: [], completeTop3Days: []),
                                    now: d(7), calendar: cal)
        XCTAssertNil(r.completionRate)
        XCTAssertNil(r.actualToEstimate)
        XCTAssertEqual(r.perDay, Array(repeating: 0, count: 7))
    }
}
