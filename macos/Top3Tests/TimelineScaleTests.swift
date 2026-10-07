import XCTest

final class TimelineScaleTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US_POSIX")
        c.firstWeekday = 2
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: Zoom levels

    func testZoomLevelsAreOrderedAndNamed() {
        let ppd = TimelineZoom.allCases.map(\.pointsPerDay)
        XCTAssertEqual(ppd, ppd.sorted(), "decade, year, quarter, month zoom in further each time")
        XCTAssertEqual(TimelineZoom.nearest(to: 2), .year)
        XCTAssertEqual(TimelineZoom.nearest(to: 0.25), .decade)
        XCTAssertEqual(TimelineZoom.nearest(to: 6), .quarter)
        XCTAssertEqual(TimelineZoom.nearest(to: 50), .month)
        XCTAssertEqual(TimelineZoom.nearest(to: .nan), .year, "bad input falls back to the year view")
        for zoom in TimelineZoom.allCases {
            XCTAssertEqual(TimelineZoom.nearest(to: zoom.pointsPerDay), zoom)
            XCTAssertGreaterThan(zoom.newGoalDays, 0)
            XCTAssertGreaterThan(zoom.nudgeDays, 0)
        }
    }

    func testZoomSteps() {
        XCTAssertEqual(TimelineZoom.zoomedIn(from: TimelineZoom.decade.pointsPerDay), TimelineZoom.year.pointsPerDay)
        XCTAssertEqual(TimelineZoom.zoomedIn(from: TimelineZoom.year.pointsPerDay), TimelineZoom.quarter.pointsPerDay)
        XCTAssertEqual(TimelineZoom.zoomedOut(from: TimelineZoom.month.pointsPerDay), TimelineZoom.quarter.pointsPerDay)
        XCTAssertEqual(TimelineZoom.zoomedIn(from: 3), TimelineZoom.quarter.pointsPerDay, "from between levels, the next level in")
        XCTAssertEqual(TimelineZoom.zoomedOut(from: 3), TimelineZoom.year.pointsPerDay)
        XCTAssertEqual(TimelineZoom.zoomedIn(from: TimelineZoom.month.pointsPerDay), TimelineZoom.month.pointsPerDay * TimelineZoom.stepFactor)
        XCTAssertEqual(TimelineZoom.zoomedIn(from: TimelineZoom.maxPointsPerDay), TimelineZoom.maxPointsPerDay, "stops at the limit")
        XCTAssertEqual(TimelineZoom.zoomedOut(from: TimelineZoom.minPointsPerDay), TimelineZoom.minPointsPerDay)
        XCTAssertEqual(TimelineZoom.clamp(1_000), TimelineZoom.maxPointsPerDay)
        XCTAssertEqual(TimelineZoom.clamp(-1), TimelineZoom.year.pointsPerDay)
    }

    // MARK: Date and position

    func testDateToXAndBack() {
        let s = TimelineScale(origin: day(2026, 1, 1), pointsPerDay: 10)
        XCTAssertEqual(s.x(day(2026, 1, 1)), 0)
        XCTAssertEqual(s.x(day(2026, 1, 11)), 100, accuracy: 1e-9)
        XCTAssertEqual(s.x(day(2025, 12, 31)), -10, accuracy: 1e-9)
        XCTAssertEqual(s.date(atX: 100), day(2026, 1, 11))
        XCTAssertEqual(s.date(atX: s.x(day(2031, 7, 4))).timeIntervalSince(day(2031, 7, 4)), 0, accuracy: 1e-6)
        let v = s.visibleInterval(width: 300, margin: 20)
        XCTAssertEqual(v.start, day(2025, 12, 30))
        XCTAssertEqual(v.end, day(2026, 2, 2))
    }

    func testPanning() {
        let s = TimelineScale(origin: day(2026, 1, 1), pointsPerDay: 10)
        let right = s.panned(by: 50)
        XCTAssertEqual(right.origin, cal.date(byAdding: .day, value: -5, to: day(2026, 1, 1)), "dragging right shows earlier dates")
        XCTAssertEqual(right.x(day(2026, 1, 1)), 50, accuracy: 1e-9)
        XCTAssertEqual(s.panned(by: -50).panned(by: 50), s)
        XCTAssertEqual(s.panned(by: .nan), s)
    }

    func testZoomKeepsTheDateUnderThePointer() {
        let s = TimelineScale(origin: day(2026, 1, 1), pointsPerDay: 2)
        for anchor in [0.0, 137.5, 600] {
            let before = s.date(atX: anchor)
            let z = s.zoomed(by: 3.7, anchorX: anchor)
            XCTAssertEqual(z.pointsPerDay, 7.4, accuracy: 1e-9)
            XCTAssertEqual(z.date(atX: anchor).timeIntervalSince(before), 0, accuracy: 1e-3)
            let out = s.zoomed(to: TimelineZoom.decade.pointsPerDay, anchorX: anchor)
            XCTAssertEqual(out.date(atX: anchor).timeIntervalSince(before), 0, accuracy: 1e-3)
        }
        let clamped = s.zoomed(by: 1_000, anchorX: 100)
        XCTAssertEqual(clamped.pointsPerDay, TimelineZoom.maxPointsPerDay)
        XCTAssertEqual(clamped.date(atX: 100).timeIntervalSince(s.date(atX: 100)), 0, accuracy: 1e-3, "even when clamped")
        XCTAssertEqual(s.zoomed(by: 0, anchorX: 10), s, "a zero factor is ignored")
    }

    func testPlacingAndRevealing() {
        let today = day(2026, 10, 7)
        let s = TimelineScale.placing(today, atFraction: 0.3, width: 1000, pointsPerDay: 2)
        XCTAssertEqual(s.x(today), 300, accuracy: 1e-9)

        // Already visible: no change.
        XCTAssertEqual(s.revealing(start: today, end: day(2026, 11, 1), width: 1000, padding: 20), s)
        // Off to the right: pans just enough.
        let later = s.revealing(start: day(2027, 8, 1), end: day(2027, 12, 1), width: 1000, padding: 20)
        XCTAssertEqual(later.x(day(2027, 12, 1)), 980, accuracy: 1e-6)
        // Off to the left: its start lands at the padding.
        let earlier = s.revealing(start: day(2025, 1, 1), end: day(2025, 2, 1), width: 1000, padding: 20)
        XCTAssertEqual(earlier.x(day(2025, 1, 1)), 20, accuracy: 1e-6)
        // Wider than the view: its start goes to the left edge.
        let wide = s.revealing(start: day(2020, 1, 1), end: day(2030, 1, 1), width: 1000, padding: 20)
        XCTAssertEqual(wide.x(day(2020, 1, 1)), 20, accuracy: 1e-6)
    }

    func testClampingToBounds() {
        let bounds = DateInterval(start: day(2000, 1, 1), end: day(2100, 1, 1))
        let early = TimelineScale(origin: day(1990, 1, 1), pointsPerDay: 2).clamped(to: bounds, width: 730)
        XCTAssertEqual(early.origin, day(2000, 1, 1))
        let late = TimelineScale(origin: day(2099, 12, 1), pointsPerDay: 2).clamped(to: bounds, width: 730)
        XCTAssertEqual(late.visibleInterval(width: 730).end.timeIntervalSince(day(2100, 1, 1)), 0, accuracy: 1e-3)
        let fine = TimelineScale(origin: day(2026, 1, 1), pointsPerDay: 2)
        XCTAssertEqual(fine.clamped(to: bounds, width: 730), fine)
    }

    func testInterpolation() {
        let a = TimelineScale(origin: day(2026, 1, 1), pointsPerDay: 2)
        let b = a.zoomed(to: 8, anchorX: 250)
        XCTAssertEqual(TimelineScale.interpolate(from: a, to: b, anchorX: 250, progress: 0), a)
        XCTAssertEqual(TimelineScale.interpolate(from: a, to: b, anchorX: 250, progress: 1), b)
        let mid = TimelineScale.interpolate(from: a, to: b, anchorX: 250, progress: 0.5)
        XCTAssertEqual(mid.pointsPerDay, 4, accuracy: 1e-9, "zoom eases on a log scale")
        XCTAssertEqual(mid.date(atX: 250).timeIntervalSince(a.date(atX: 250)), 0, accuracy: 1e-3, "the anchor date stays put")

        let pan = a.panned(by: -400)
        let half = TimelineScale.interpolate(from: a, to: pan, anchorX: 0, progress: 0.5)
        XCTAssertEqual(half.x(day(2026, 1, 1)), -200, accuracy: 1e-6)
        XCTAssertEqual(TimelineScale.easeOut(0), 0)
        XCTAssertEqual(TimelineScale.easeOut(1), 1)
        XCTAssertGreaterThan(TimelineScale.easeOut(0.5), 0.5)
        XCTAssertEqual(TimelineScale.easeOut(2), 1)
    }

    // MARK: Axis

    func testAxisUnitsPerZoom() {
        XCTAssertEqual(TimelineAxis.minorUnit(forPointsPerDay: TimelineZoom.decade.pointsPerDay), .year)
        XCTAssertEqual(TimelineAxis.minorUnit(forPointsPerDay: TimelineZoom.year.pointsPerDay), .month)
        XCTAssertEqual(TimelineAxis.minorUnit(forPointsPerDay: TimelineZoom.quarter.pointsPerDay), .week)
        XCTAssertEqual(TimelineAxis.minorUnit(forPointsPerDay: TimelineZoom.month.pointsPerDay), .day)
        XCTAssertEqual(TimelineAxis.minorUnit(forPointsPerDay: TimelineZoom.minPointsPerDay), .year)
    }

    func testYearAxis() {
        let axis = TimelineAxis.make(for: DateInterval(start: day(2026, 10, 15), end: day(2027, 3, 1)), pointsPerDay: 2, calendar: cal)
        XCTAssertEqual(axis.majorUnit, .year)
        XCTAssertEqual(axis.minorUnit, .month)
        XCTAssertEqual(axis.minor.map(\.label), ["Oct", "Nov", "Dec", "Jan", "Feb"])
        XCTAssertEqual(axis.minor.first?.date, day(2026, 10, 1), "the first tick sits at or before the left edge")
        XCTAssertEqual(axis.major.map(\.label), ["2026", "2027"])
        XCTAssertEqual(axis.major.map(\.date), [day(2026, 1, 1), day(2027, 1, 1)])
    }

    func testDecadeAxis() {
        let axis = TimelineAxis.make(for: DateInterval(start: day(2024, 6, 1), end: day(2031, 2, 1)), pointsPerDay: 0.2, calendar: cal)
        XCTAssertEqual(axis.minor.map(\.label), ["2024", "2025", "2026", "2027", "2028", "2029", "2030", "2031"])
        XCTAssertEqual(axis.major.map(\.label), ["2020s", "2030s"])
        XCTAssertEqual(axis.major.first?.date, day(2020, 1, 1))

        let far = TimelineAxis.make(for: DateInterval(start: day(2020, 1, 1), end: day(2030, 1, 1)), pointsPerDay: 0.08, calendar: cal)
        XCTAssertEqual(far.minor.count, 10, "every year still gets a line")
        XCTAssertEqual(far.minor.filter { !$0.label.isEmpty }.map(\.label), ["2020", "2022", "2024", "2026", "2028"],
                       "crowded labels skip to every other year")
    }

    func testQuarterAxis() {
        // 5 Oct 2026 is a Monday; weeks start on Monday in this calendar.
        let axis = TimelineAxis.make(for: DateInterval(start: day(2026, 10, 7), end: day(2026, 11, 3)), pointsPerDay: 8, calendar: cal)
        XCTAssertEqual(axis.minorUnit, .week)
        XCTAssertEqual(axis.minor.map(\.date), [day(2026, 10, 5), day(2026, 10, 12), day(2026, 10, 19), day(2026, 10, 26), day(2026, 11, 2)])
        XCTAssertEqual(axis.minor.map(\.label), ["5", "12", "19", "26", "2"])
        XCTAssertEqual(axis.major.map(\.label), ["October 2026", "November 2026"])
    }

    func testMonthAxis() {
        let axis = TimelineAxis.make(for: DateInterval(start: day(2026, 10, 30), end: day(2026, 11, 3)), pointsPerDay: 28, calendar: cal)
        XCTAssertEqual(axis.minorUnit, .day)
        XCTAssertEqual(axis.minor.map(\.label), ["30", "31", "1", "2"])
        XCTAssertEqual(axis.minor.map(\.isWeekend), [false, true, true, false], "31 Oct and 1 Nov 2026 are a weekend")
        XCTAssertEqual(axis.major.map(\.label), ["October 2026", "November 2026"])
    }

    func testQuarterUnitBoundaries() {
        XCTAssertEqual(TimelineAxisUnit.quarter.start(of: day(2026, 8, 19), calendar: cal), day(2026, 7, 1))
        XCTAssertEqual(TimelineAxisUnit.decade.start(of: day(2029, 12, 31), calendar: cal), day(2020, 1, 1))
        XCTAssertEqual(TimelineAxis.label(.quarter, day(2026, 8, 1), calendar: cal, isMinor: true, yearStride: 1), "Q3")
    }

    func testAxisTickCountIsCapped() {
        let axis = TimelineAxis.make(for: DateInterval(start: day(1900, 1, 1), end: day(2100, 1, 1)), pointsPerDay: 80, calendar: cal)
        XCTAssertLessThanOrEqual(axis.minor.count, TimelineAxis.maximumTicks)
    }
}
