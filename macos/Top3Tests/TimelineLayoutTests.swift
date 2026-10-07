import XCTest

final class TimelineLayoutTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func goal(_ title: String = "Goal", lane: UUID = UUID(), type: GoalType = .goal, status: GoalStatus = .active,
                      start: Date? = nil, target: Date? = nil, created: Date? = nil, progress: Int = 0) -> TimelineGoal {
        TimelineGoal(id: UUID(), laneID: lane, title: title, type: type, status: status, startDate: start, targetDate: target,
                     createdAt: created ?? day(2026, 1, 1), progress: progress)
    }

    // MARK: Spans

    func testSpansFromGoalDates() {
        let both = TimelineDates.span(type: .goal, start: day(2026, 3, 1), target: day(2026, 6, 30), createdAt: day(2026, 1, 1), calendar: cal)
        XCTAssertEqual(both, DaySpan(start: day(2026, 3, 1), end: day(2026, 6, 30)))
        XCTAssertEqual(both?.days(calendar: cal), 122)
        XCTAssertEqual(both?.visualEnd(calendar: cal), day(2026, 7, 1), "the bar covers its last day")

        let swapped = TimelineDates.span(type: .goal, start: day(2026, 6, 30), target: day(2026, 3, 1), createdAt: .distantPast, calendar: cal)
        XCTAssertEqual(swapped, both, "dates out of order still make a forward span")

        let targetOnly = TimelineDates.span(type: .goal, start: nil, target: day(2026, 9, 1), createdAt: day(2026, 2, 3).addingTimeInterval(3600), calendar: cal)
        XCTAssertEqual(targetOnly, DaySpan(start: day(2026, 2, 3), end: day(2026, 9, 1)), "runs from the day it was created")

        let createdLater = TimelineDates.span(type: .goal, start: nil, target: day(2026, 1, 5), createdAt: day(2026, 4, 1), calendar: cal)
        XCTAssertEqual(createdLater, DaySpan(start: day(2026, 1, 5), end: day(2026, 1, 5)))

        let startOnly = TimelineDates.span(type: .habitTarget, start: day(2026, 5, 5), target: nil, createdAt: day(2026, 1, 1), calendar: cal)
        XCTAssertEqual(startOnly?.isSingleDay, true)

        XCTAssertNil(TimelineDates.span(type: .goal, start: nil, target: nil, createdAt: day(2026, 1, 1), calendar: cal), "undated")
    }

    func testMilestonesAreSingleDates() {
        let m = TimelineDates.span(type: .milestone, start: day(2026, 8, 1), target: day(2026, 11, 15), createdAt: day(2026, 1, 1), calendar: cal)
        XCTAssertEqual(m, DaySpan(start: day(2026, 11, 15), end: day(2026, 11, 15)), "a milestone sits on its target")
        let startOnly = TimelineDates.span(type: .milestone, start: day(2026, 8, 1), target: nil, createdAt: day(2026, 1, 1), calendar: cal)
        XCTAssertEqual(startOnly, DaySpan(start: day(2026, 8, 1), end: day(2026, 8, 1)))
        XCTAssertNil(TimelineDates.span(type: .milestone, start: nil, target: nil, createdAt: day(2026, 1, 1), calendar: cal))
    }

    func testOverdue() {
        let span = DaySpan(start: day(2026, 1, 1), end: day(2026, 10, 6))
        let today = day(2026, 10, 7).addingTimeInterval(9 * 3600)
        XCTAssertTrue(TimelineDates.isOverdue(status: .active, span: span, today: today, calendar: cal))
        XCTAssertFalse(TimelineDates.isOverdue(status: .planned, span: span, today: today, calendar: cal), "only active goals")
        XCTAssertFalse(TimelineDates.isOverdue(status: .done, span: span, today: today, calendar: cal))
        XCTAssertFalse(TimelineDates.isOverdue(status: .active, span: DaySpan(start: day(2026, 1, 1), end: day(2026, 10, 7)), today: today, calendar: cal),
                       "due today is not overdue yet")
        XCTAssertFalse(TimelineDates.isOverdue(status: .active, span: nil, today: today, calendar: cal))
    }

    func testNewGoalDates() {
        let g = TimelineDates.newGoalDates(type: .goal, day: day(2026, 10, 7).addingTimeInterval(5000), days: 30, calendar: cal)
        XCTAssertEqual(g.start, day(2026, 10, 7))
        XCTAssertEqual(g.target, day(2026, 11, 5), "30 days, both ends included")
        let m = TimelineDates.newGoalDates(type: .milestone, day: day(2026, 10, 7), days: 30, calendar: cal)
        XCTAssertNil(m.start)
        XCTAssertEqual(m.target, day(2026, 10, 7))
        XCTAssertEqual(TimelineDates.newGoalDates(type: .goal, day: day(2026, 10, 7), days: 0, calendar: cal).target, day(2026, 10, 7))
    }

    // MARK: Culling

    func testCullingKeepsOnlyVisibleGoals() {
        let lane = UUID()
        var goals: [TimelineGoal] = []
        for i in 0..<240 {
            let start = cal.date(byAdding: .day, value: i * 15, to: day(2020, 1, 1))!
            goals.append(goal("G\(i)", lane: lane, start: start, target: cal.date(byAdding: .day, value: 20, to: start)))
        }
        goals.append(goal("Long", lane: lane, start: day(2019, 1, 1), target: day(2035, 1, 1)))
        goals.append(goal("Undated", lane: lane))
        let window = DateInterval(start: day(2026, 1, 1), end: day(2026, 3, 1))
        let visible = TimelineCulling.visible(goals, in: window) { g in
            TimelineDates.span(of: g, calendar: cal).map { ($0.start, $0.visualEnd(calendar: cal)) }
        }
        XCTAssertTrue(visible.contains { $0.title == "Long" }, "a bar spanning the whole window is visible")
        XCTAssertFalse(visible.contains { $0.title == "Undated" })
        XCTAssertLessThan(visible.count, 10, "a few out of 242")
        for g in visible {
            let s = TimelineDates.span(of: g, calendar: cal)!
            XCTAssertTrue(s.start < window.end && s.visualEnd(calendar: cal) > window.start)
        }
        let edge = goal("Ends at the edge", start: day(2025, 12, 1), target: day(2025, 12, 31))
        XCTAssertTrue(TimelineCulling.visible([edge], in: window) { g in
            TimelineDates.span(of: g, calendar: cal).map { ($0.start, $0.visualEnd(calendar: cal)) }
        }.isEmpty, "a bar that ends where the window starts is out")
    }

    func testClippingLongBars() {
        XCTAssertEqual(TimelineCulling.clip(-50_000, 120, width: 800, overscan: 8)?.x0, -8)
        XCTAssertEqual(TimelineCulling.clip(100, 90_000, width: 800, overscan: 8)?.x1, 808)
        XCTAssertNil(TimelineCulling.clip(900, 1000, width: 800, overscan: 8))
        XCTAssertEqual(TimelineCulling.clip(10, 20, width: 800, overscan: 8)?.x0, 10)
    }

    // MARK: Rows

    func testPackingIntoRows() {
        let a = TimelinePacking.Item(id: UUID(), x0: 0, x1: 100)
        let b = TimelinePacking.Item(id: UUID(), x0: 50, x1: 150)
        let c = TimelinePacking.Item(id: UUID(), x0: 104, x1: 200)
        let d = TimelinePacking.Item(id: UUID(), x0: 102, x1: 120)
        let rows = TimelinePacking.rows([c, b, a, d], gap: 4)
        XCTAssertEqual(rows[a.id], 0)
        XCTAssertEqual(rows[b.id], 1, "overlaps a")
        XCTAssertEqual(rows[d.id], 2, "too close to a (gap) and overlapping b")
        XCTAssertEqual(rows[c.id], 0, "fits after a with the gap")
        XCTAssertEqual(TimelinePacking.rowCount(rows), 3)
        XCTAssertEqual(TimelinePacking.rowCount([:]), 0)

        // Panning moves everything by the same amount, so rows stay put.
        let shifted = TimelinePacking.rows([a, b, c, d].map { TimelinePacking.Item(id: $0.id, x0: $0.x0 - 5_000, x1: $0.x1 - 5_000) }, gap: 4)
        XCTAssertEqual(shifted, rows)
        XCTAssertEqual(TimelinePacking.estimatedLabelWidth("Run", characterWidth: 6, padding: 10), 28)
    }

    func testPackingManyGoalsIsQuick() {
        let items = (0..<2_000).map { i in TimelinePacking.Item(id: UUID(), x0: Double(i * 7 % 3_000), x1: Double(i * 7 % 3_000 + 120)) }
        measure { _ = TimelinePacking.rows(items, gap: 4) }
    }

    // MARK: Dragging

    func testDayDeltaSnapsToWholeDays() {
        XCTAssertEqual(TimelineDrag.dayDelta(translation: 41, pointsPerDay: 28), 1)
        XCTAssertEqual(TimelineDrag.dayDelta(translation: 13, pointsPerDay: 28), 0)
        XCTAssertEqual(TimelineDrag.dayDelta(translation: -43, pointsPerDay: 28), -2)
        XCTAssertEqual(TimelineDrag.dayDelta(translation: 10, pointsPerDay: 0.2), 50)
        XCTAssertEqual(TimelineDrag.dayDelta(translation: .infinity, pointsPerDay: 2), 0)
        XCTAssertEqual(TimelineDrag.dayDelta(translation: 1e12, pointsPerDay: 0.08), 36_500, "bounded to a century")
    }

    func testMoveKeepsLength() {
        let span = DaySpan(start: day(2026, 3, 1), end: day(2026, 3, 31))
        let moved = TimelineDrag.moved(span, by: 10, calendar: cal)
        XCTAssertEqual(moved, DaySpan(start: day(2026, 3, 11), end: day(2026, 4, 10)))
        XCTAssertEqual(moved.days(calendar: cal), span.days(calendar: cal))
        XCTAssertEqual(TimelineDrag.moved(span, by: 0, calendar: cal), span)
    }

    func testResizeBounds() {
        let span = DaySpan(start: day(2026, 3, 1), end: day(2026, 3, 10))
        XCTAssertEqual(TimelineDrag.resized(span, edge: .end, by: 5, calendar: cal).end, day(2026, 3, 15))
        XCTAssertEqual(TimelineDrag.resized(span, edge: .start, by: -3, calendar: cal).start, day(2026, 2, 26))
        let tooFarLeft = TimelineDrag.resized(span, edge: .end, by: -40, calendar: cal)
        XCTAssertEqual(tooFarLeft, DaySpan(start: day(2026, 3, 1), end: day(2026, 3, 1)), "the end never passes the start: one day minimum")
        let tooFarRight = TimelineDrag.resized(span, edge: .start, by: 40, calendar: cal)
        XCTAssertEqual(tooFarRight, DaySpan(start: day(2026, 3, 10), end: day(2026, 3, 10)))
        XCTAssertEqual(tooFarRight.days(calendar: cal), 1)
    }

    func testDatesAfterMove() {
        let shown = DaySpan(start: day(2026, 2, 1), end: day(2026, 6, 30))
        // Both dates: both move.
        let both = TimelineDrag.datesAfterMove(type: .goal, start: day(2026, 2, 1), target: day(2026, 6, 30), shown: shown, by: 7, calendar: cal)
        XCTAssertEqual(both.start, day(2026, 2, 8))
        XCTAssertEqual(both.target, day(2026, 7, 7))
        // Target only, shown from its creation day: the start gets written down so the bar moves whole.
        let targetOnly = TimelineDrag.datesAfterMove(type: .goal, start: nil, target: day(2026, 6, 30), shown: shown, by: -1, calendar: cal)
        XCTAssertEqual(targetOnly.start, day(2026, 1, 31))
        XCTAssertEqual(targetOnly.target, day(2026, 6, 29))
        // Start only: stays without a target.
        let startOnly = TimelineDrag.datesAfterMove(type: .goal, start: day(2026, 2, 1), target: nil,
                                                    shown: DaySpan(start: day(2026, 2, 1), end: day(2026, 2, 1)), by: 3, calendar: cal)
        XCTAssertEqual(startOnly.start, day(2026, 2, 4))
        XCTAssertNil(startOnly.target)
        // Milestone: its date (and start, if any) shift; it stays a single date.
        let milestone = TimelineDrag.datesAfterMove(type: .milestone, start: nil, target: day(2026, 11, 15),
                                                    shown: DaySpan(start: day(2026, 11, 15), end: day(2026, 11, 15)), by: 2, calendar: cal)
        XCTAssertNil(milestone.start)
        XCTAssertEqual(milestone.target, day(2026, 11, 17))
    }

    func testDatesAfterResize() {
        let shown = DaySpan(start: day(2026, 2, 1), end: day(2026, 2, 10))
        let r = TimelineDrag.datesAfterResize(shown: shown, edge: .end, by: -20, calendar: cal)
        XCTAssertEqual(r.start, day(2026, 2, 1))
        XCTAssertEqual(r.target, day(2026, 2, 1))
    }

    // MARK: Keyboard navigation

    func testArrowKeyNavigation() {
        func item(_ lane: Int, _ m: Int, _ d: Int, _ days: Int = 10) -> TimelineNavigation.Item {
            TimelineNavigation.Item(id: UUID(), lane: lane, span: DaySpan(start: day(2026, m, d), end: cal.date(byAdding: .day, value: days, to: day(2026, m, d))!))
        }
        let a = item(0, 1, 1), b = item(0, 5, 1), c = item(0, 9, 1)
        let d = item(1, 4, 20), e = item(1, 12, 1)
        let f = item(3, 9, 5)
        let all = [c, a, f, e, b, d]
        XCTAssertEqual(TimelineNavigation.next(from: nil, direction: .right, items: all), a.id, "nothing selected: the first goal")
        XCTAssertEqual(TimelineNavigation.next(from: a.id, direction: .right, items: all), b.id)
        XCTAssertEqual(TimelineNavigation.next(from: b.id, direction: .left, items: all), a.id)
        XCTAssertEqual(TimelineNavigation.next(from: c.id, direction: .right, items: all), c.id, "stays at the lane's end")
        XCTAssertEqual(TimelineNavigation.next(from: b.id, direction: .down, items: all), d.id, "nearest in time in the lane below")
        XCTAssertEqual(TimelineNavigation.next(from: e.id, direction: .down, items: all), f.id, "skips lanes with nothing in them")
        XCTAssertEqual(TimelineNavigation.next(from: f.id, direction: .up, items: all), e.id)
        XCTAssertEqual(TimelineNavigation.next(from: a.id, direction: .up, items: all), a.id, "nothing above")
        XCTAssertNil(TimelineNavigation.next(from: nil, direction: .down, items: []))
    }

    // MARK: Lane summary

    func testLaneSummary() {
        let lane = UUID()
        let goals = [goal(lane: lane, status: .active, start: day(2026, 1, 1), target: day(2026, 6, 1), progress: 40),
                     goal(lane: lane, status: .active, start: day(2026, 1, 1), target: day(2026, 6, 1), progress: 60),
                     goal(lane: lane, status: .done, start: day(2025, 1, 1), target: day(2025, 6, 1), progress: 100),
                     goal(lane: lane, status: .dropped, start: day(2025, 1, 1), target: day(2025, 6, 1), progress: 0),
                     goal(lane: lane, status: .idea, progress: 0)]
        let s = LaneSummary.make(goals, calendar: cal)
        XCTAssertEqual(s.active, 2)
        XCTAssertEqual(s.percent, 50, "dropped goals do not count")
        XCTAssertEqual(s.undated, 1)
        XCTAssertEqual(s.text, "2 active, 50%")
        XCTAssertEqual(LaneSummary.make([], calendar: cal).text, "No goals yet")
        XCTAssertEqual(LaneSummary.make([goal(status: .planned, progress: 0)], calendar: cal).text, "1 goal, 0%")
        XCTAssertEqual(LaneSummary.make([goal(status: .done, progress: 100), goal(status: .idea)], calendar: cal).text, "2 goals, 50%")
    }

    // MARK: Lane reordering

    func testLaneReorderTarget() {
        let heights: [Double] = [60, 40, 80, 40]
        XCTAssertEqual(LaneReorder.targetIndex(from: 0, offset: 0, heights: heights), 0)
        XCTAssertEqual(LaneReorder.targetIndex(from: 0, offset: 55, heights: heights), 1, "past the middle of the second lane")
        XCTAssertEqual(LaneReorder.targetIndex(from: 0, offset: 45, heights: heights), 0, "not yet past it")
        XCTAssertEqual(LaneReorder.targetIndex(from: 0, offset: 25, heights: heights), 0)
        XCTAssertEqual(LaneReorder.targetIndex(from: 3, offset: -1000, heights: heights), 0)
        XCTAssertEqual(LaneReorder.targetIndex(from: 1, offset: 1000, heights: heights), 3)

        let ids = [UUID(), UUID(), UUID(), UUID()]
        XCTAssertEqual(LaneReorder.beforeID(moving: 0, to: 1, ids: ids), ids[2])
        XCTAssertNil(LaneReorder.beforeID(moving: 0, to: 3, ids: ids), "to the end")
        XCTAssertEqual(LaneReorder.beforeID(moving: 3, to: 0, ids: ids), ids[0])
        XCTAssertEqual(VisionOrder.moving(ids[0], before: LaneReorder.beforeID(moving: 0, to: 1, ids: ids), in: ids), [ids[1], ids[0], ids[2], ids[3]])
    }
}
