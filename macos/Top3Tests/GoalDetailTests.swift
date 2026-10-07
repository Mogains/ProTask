import XCTest

final class GoalDetailTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 9) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    // MARK: Links

    func testLinkRelationEdges() {
        XCTAssertEqual(GoalLinkRelation.dependsOn.edge(goal: a, other: b), GoalEdge(upstream: b, downstream: a))
        XCTAssertEqual(GoalLinkRelation.neededFor.edge(goal: a, other: b), GoalEdge(upstream: a, downstream: b))
    }

    func testLinkChecksRefuseSelfDuplicatesAndLoops() {
        // b depends on a, c depends on b.
        let edges = [GoalEdge(upstream: a, downstream: b), GoalEdge(upstream: b, downstream: c)]
        XCTAssertEqual(GoalLinks.check(goal: a, other: a, relation: .dependsOn, edges: edges), .sameGoal)
        XCTAssertEqual(GoalLinks.check(goal: a, other: a, relation: .neededFor, edges: []), .sameGoal)
        XCTAssertEqual(GoalLinks.check(goal: b, other: a, relation: .dependsOn, edges: edges), .alreadyLinked)
        XCTAssertEqual(GoalLinks.check(goal: a, other: b, relation: .neededFor, edges: edges), .alreadyLinked)
        // a depending on b (or on c, further down) closes a loop.
        XCTAssertEqual(GoalLinks.check(goal: a, other: b, relation: .dependsOn, edges: edges), .wouldLoop)
        XCTAssertEqual(GoalLinks.check(goal: a, other: c, relation: .dependsOn, edges: edges), .wouldLoop)
        XCTAssertEqual(GoalLinks.check(goal: c, other: a, relation: .neededFor, edges: edges), .wouldLoop)
        // Shortcuts that keep the direction are fine: c depends on a directly.
        XCTAssertEqual(GoalLinks.check(goal: c, other: a, relation: .dependsOn, edges: edges), .allowed)
        XCTAssertEqual(GoalLinks.check(goal: d, other: a, relation: .dependsOn, edges: edges), .allowed)
        XCTAssertEqual(GoalLinks.check(goal: d, other: c, relation: .neededFor, edges: edges), .allowed)
        XCTAssertNil(GoalLinkCheck.allowed.reason)
        XCTAssertEqual(GoalLinkCheck.wouldLoop.reason, "Would make a loop")
    }

    func testEveryAllowedLinkKeepsTheGraphAcyclic() {
        let ids = [a, b, c, d]
        var edges: [GoalEdge] = []
        for goal in ids {
            for other in ids {
                for relation in GoalLinkRelation.allCases where GoalLinks.check(goal: goal, other: other, relation: relation, edges: edges).isAllowed {
                    edges.append(relation.edge(goal: goal, other: other))
                }
            }
        }
        XCTAssertFalse(edges.isEmpty)
        for id in ids {
            XCTAssertFalse(GoalGraph.downstream(of: id, in: edges).contains(id), "no goal reaches itself")
        }
    }

    func testDirectNeighbors() {
        let edges = [GoalEdge(upstream: a, downstream: b), GoalEdge(upstream: c, downstream: b),
                     GoalEdge(upstream: b, downstream: d), GoalEdge(upstream: a, downstream: b)]
        XCTAssertEqual(GoalLinks.dependsOn(b, edges: edges), [a, c], "upstream, without repeats")
        XCTAssertEqual(GoalLinks.neededFor(b, edges: edges), [d])
        XCTAssertEqual(GoalLinks.dependsOn(a, edges: edges), [])
        XCTAssertEqual(GoalLinks.neededFor(a, edges: edges), [b])
    }

    func testCandidatesListAllowedFirst() {
        let edges = [GoalEdge(upstream: a, downstream: b)]
        let list = GoalLinks.candidates(for: a, relation: .dependsOn, among: [a, b, c, d, c], edges: edges)
        XCTAssertEqual(list.map(\.id), [c, d, b], "self dropped, repeats dropped, the loop last")
        XCTAssertEqual(list.last?.check, .wouldLoop)
    }

    func testLinkSearch() {
        let titles = ["Gym", "Finish quarterly report", "Switch the payment webhooks", "Grocery run"]
        XCTAssertEqual(LinkSearch.filter(titles, query: "", title: { $0 }), titles)
        XCTAssertEqual(LinkSearch.filter(titles, query: "   ", title: { $0 }), titles)
        XCTAssertEqual(LinkSearch.filter(titles, query: "gr", title: { $0 }).first, "Grocery run")
        XCTAssertEqual(LinkSearch.filter(titles, query: "webh", title: { $0 }), ["Switch the payment webhooks"])
        XCTAssertEqual(LinkSearch.filter(titles, query: "zzz", title: { $0 }), [])
    }

    // MARK: Log

    func testLogOrderingIsNewestFirst() {
        let e1 = GoalLogEntry(id: a, date: day(2026, 9, 1), createdAt: day(2026, 9, 1), text: "one")
        let e2 = GoalLogEntry(id: b, date: day(2026, 9, 20), createdAt: day(2026, 9, 2), text: "backdated later day")
        let e3 = GoalLogEntry(id: c, date: day(2026, 9, 20, hour: 7), createdAt: day(2026, 9, 21), text: "same day, written later")
        let e4 = GoalLogEntry(id: d, date: day(2026, 8, 15), createdAt: day(2026, 10, 1), text: "old day, written last")
        let ordered = GoalLogOrder.newestFirst([e1, e4, e2, e3], calendar: cal)
        XCTAssertEqual(ordered.map(\.text), ["same day, written later", "backdated later day", "one", "old day, written last"])
        XCTAssertEqual(GoalLogOrder.newestFirst([], calendar: cal), [])
    }

    func testLogEntryValidity() {
        XCTAssertFalse(GoalLogOrder.isValid(text: "  \n", metricValue: nil))
        XCTAssertTrue(GoalLogOrder.isValid(text: "Long run 14k", metricValue: nil))
        XCTAssertTrue(GoalLogOrder.isValid(text: "", metricValue: 14))
        XCTAssertFalse(GoalLogOrder.isValid(text: "", metricValue: .nan))
    }

    func testLoggedValueUpdatesCurrentOnlyWhenLatest() {
        let others = [day(2026, 9, 1), day(2026, 9, 10)]
        XCTAssertTrue(GoalLogOrder.updatesCurrent(entryDate: day(2026, 9, 12), otherValueDates: others, calendar: cal))
        XCTAssertTrue(GoalLogOrder.updatesCurrent(entryDate: day(2026, 9, 10, hour: 6), otherValueDates: others, calendar: cal), "same day counts")
        XCTAssertFalse(GoalLogOrder.updatesCurrent(entryDate: day(2026, 9, 5), otherValueDates: others, calendar: cal))
        XCTAssertTrue(GoalLogOrder.updatesCurrent(entryDate: day(2026, 1, 1), otherValueDates: [], calendar: cal))
    }

    // MARK: Metric series

    func testMetricSeriesStartLogsAndToday() {
        let metric = GoalMetric(name: "Long run", start: 5, current: 13, target: 21.1, unit: "km")
        let logs = [
            GoalLogEntry(id: a, date: day(2026, 8, 1), createdAt: day(2026, 8, 1), text: "", metricValue: 8),
            GoalLogEntry(id: b, date: day(2026, 9, 1), createdAt: day(2026, 9, 1), text: "", metricValue: 10),
            GoalLogEntry(id: c, date: day(2026, 9, 1, hour: 20), createdAt: day(2026, 9, 2), text: "fixed", metricValue: 11),
            GoalLogEntry(id: d, date: day(2026, 9, 5), createdAt: day(2026, 9, 5), text: "no number"),
        ]
        let points = MetricSeries.points(metric: metric, startDate: day(2026, 7, 1), createdAt: day(2026, 6, 1), logs: logs,
                                         today: day(2026, 10, 7), calendar: cal)
        XCTAssertEqual(points.map(\.value), [5, 8, 11, 13], "one value per day, the last written wins")
        XCTAssertEqual(points.map(\.kind), [.start, .logged, .logged, .current])
        XCTAssertEqual(points.first?.date, cal.startOfDay(for: day(2026, 7, 1)))
        XCTAssertEqual(points.last?.date, cal.startOfDay(for: day(2026, 10, 7)))
        XCTAssertEqual(points.map(\.date), points.map(\.date).sorted())
    }

    func testMetricSeriesEdgeCases() {
        let metric = GoalMetric(name: "", start: 100, current: 100, target: 80)
        // Nothing logged and no movement: just the start.
        var points = MetricSeries.points(metric: metric, startDate: nil, createdAt: day(2026, 9, 1), logs: [], today: day(2026, 10, 7), calendar: cal)
        XCTAssertEqual(points.map(\.kind), [.start])
        // A start in the future is dropped; today's value stands alone.
        points = MetricSeries.points(metric: metric, startDate: day(2027, 1, 1), createdAt: day(2026, 9, 1), logs: [], today: day(2026, 10, 7), calendar: cal)
        XCTAssertEqual(points.map(\.kind), [.current])
        // The current value matches the last log: no extra point.
        let logs = [GoalLogEntry(id: a, date: day(2026, 9, 20), createdAt: day(2026, 9, 20), text: "", metricValue: 100)]
        points = MetricSeries.points(metric: metric, startDate: day(2026, 9, 1), createdAt: day(2026, 9, 1), logs: logs, today: day(2026, 10, 7), calendar: cal)
        XCTAssertEqual(points.map(\.kind), [.start, .logged])
        // A log on the start day replaces the start point.
        points = MetricSeries.points(metric: metric, startDate: day(2026, 9, 20), createdAt: day(2026, 9, 1), logs: logs, today: day(2026, 10, 7), calendar: cal)
        XCTAssertEqual(points.map(\.kind), [.logged])
        // Values that aren't numbers are skipped.
        let bad = [GoalLogEntry(id: b, date: day(2026, 9, 21), createdAt: day(2026, 9, 21), text: "", metricValue: .infinity)]
        points = MetricSeries.points(metric: metric, startDate: day(2026, 9, 1), createdAt: day(2026, 9, 1), logs: bad, today: day(2026, 10, 7), calendar: cal)
        XCTAssertEqual(points.map(\.kind), [.start])
    }

    func testMetricValueDomainIncludesTarget() {
        let points = [MetricPoint(date: day(2026, 9, 1), value: 10, kind: .start), MetricPoint(date: day(2026, 9, 2), value: 20, kind: .logged)]
        let domain = MetricSeries.valueDomain(points, target: 40, padding: 0.1)
        XCTAssertEqual(domain.lowerBound, 7, accuracy: 1e-9)
        XCTAssertEqual(domain.upperBound, 43, accuracy: 1e-9)
        let flat = MetricSeries.valueDomain([MetricPoint(date: day(2026, 9, 1), value: 0, kind: .start)], target: 0)
        XCTAssertLessThan(flat.lowerBound, flat.upperBound, "a flat series still gets a range")
        XCTAssertEqual(MetricSeries.valueDomain([], target: .nan), 0...1)
    }

    // MARK: Metric input

    func testMetricNumbersParse() {
        let us = Locale(identifier: "en_US"), de = Locale(identifier: "de_DE")
        XCTAssertEqual(MetricInput.number("12", locale: us), 12)
        XCTAssertEqual(MetricInput.number(" 21.1 ", locale: us), 21.1)
        XCTAssertEqual(MetricInput.number("14,000", locale: us), 14_000)
        XCTAssertEqual(MetricInput.number("-3.5", locale: us), -3.5)
        XCTAssertEqual(MetricInput.number("\u{2212}2", locale: us), -2)
        XCTAssertEqual(MetricInput.number("21,1", locale: de), 21.1)
        XCTAssertEqual(MetricInput.number("14.000", locale: de), 14_000)
        XCTAssertNil(MetricInput.number("", locale: us))
        XCTAssertNil(MetricInput.number("12km", locale: us))
        XCTAssertNil(MetricInput.number("inf", locale: us))
        XCTAssertNil(MetricInput.number("1e400", locale: us))
    }

    func testMetricNumbersFormat() {
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(MetricInput.format(8600, locale: us), "8,600")
        XCTAssertEqual(MetricInput.format(21.1, locale: us), "21.1")
        XCTAssertEqual(MetricInput.format(1.0 / 3, locale: us), "0.33")
        XCTAssertEqual(MetricInput.format(12, unit: "km", locale: us), "12 km")
        XCTAssertEqual(MetricInput.format(12, unit: " ", locale: us), "12")
        XCTAssertEqual(MetricInput.text(nil, locale: us), "")
        // What is shown parses back to the same number.
        for v in [0, 5, 21.1, 8600, -42.25] {
            XCTAssertEqual(MetricInput.number(MetricInput.format(v, locale: us), locale: us), v)
        }
    }

    // MARK: Progress source

    func testProgressSource() {
        let metric = GoalMetric(name: "", start: 0, current: 5, target: 10)
        XCTAssertEqual(ProgressSource.of(mode: .auto, status: .done, metric: metric), .done)
        XCTAssertEqual(ProgressSource.of(mode: .manual, status: .active, metric: metric), .manual)
        XCTAssertEqual(ProgressSource.of(mode: .auto, status: .active, metric: metric, linkedDone: 1, linkedTotal: 2), .metric)
        XCTAssertEqual(ProgressSource.of(mode: .auto, status: .active, metric: nil, linkedDone: 1, linkedTotal: 2), .tasks(done: 1, total: 2))
        XCTAssertEqual(ProgressSource.of(mode: .auto, status: .planned, metric: nil), .fallback)
        XCTAssertEqual(ProgressSource.tasks(done: 1, total: 2).explanation, "From linked tasks: 1 of 2 done.")
    }

    // MARK: Time left

    func testTimeLeft() {
        let today = day(2026, 10, 7)
        XCTAssertNil(GoalTimeLeft.describe(target: nil, status: .active, today: today, calendar: cal))
        XCTAssertNil(GoalTimeLeft.describe(target: day(2026, 12, 1), status: .done, today: today, calendar: cal))
        XCTAssertEqual(GoalTimeLeft.describe(target: day(2026, 10, 7, hour: 23), status: .active, today: today, calendar: cal), "Due today")
        XCTAssertEqual(GoalTimeLeft.describe(target: day(2026, 10, 8), status: .active, today: today, calendar: cal), "1 day left")
        XCTAssertEqual(GoalTimeLeft.describe(target: day(2026, 10, 17), status: .planned, today: today, calendar: cal), "10 days left")
        XCTAssertEqual(GoalTimeLeft.describe(target: day(2026, 11, 4), status: .active, today: today, calendar: cal), "4 weeks left")
        XCTAssertEqual(GoalTimeLeft.describe(target: day(2027, 4, 7), status: .active, today: today, calendar: cal), "6 months left")
        XCTAssertEqual(GoalTimeLeft.describe(target: day(2030, 10, 7), status: .idea, today: today, calendar: cal), "4 years left")
        XCTAssertEqual(GoalTimeLeft.describe(target: day(2026, 10, 6), status: .active, today: today, calendar: cal), "1 day past")
        XCTAssertEqual(GoalTimeLeft.describe(target: day(2026, 9, 30), status: .active, today: today, calendar: cal), "7 days past")
    }

    // MARK: Notes

    func testNotesBlocks() {
        let notes = """
        ## Plan
        - Three runs a week
          - one **long**
        - [ ] Book physio
        - [x] Buy shoes
        1. Base
        2) Build

        First line
        second line
        > Keep it easy
        > most days

        ---
        ```
        let x = 1
        ```
        #nottitle
        """
        XCTAssertEqual(NotesMarkdown.blocks(notes), [
            .heading(level: 2, text: "Plan"),
            .bullet(text: "Three runs a week", indent: 0),
            .bullet(text: "one **long**", indent: 1),
            .task(done: false, text: "Book physio", indent: 0),
            .task(done: true, text: "Buy shoes", indent: 0),
            .numbered(number: 1, text: "Base", indent: 0),
            .numbered(number: 2, text: "Build", indent: 0),
            .paragraph("First line\nsecond line"),
            .quote("Keep it easy\nmost days"),
            .rule,
            .code("let x = 1"),
            .paragraph("#nottitle"),
        ])
    }

    func testNotesBlocksEdgeCases() {
        XCTAssertEqual(NotesMarkdown.blocks(""), [])
        XCTAssertEqual(NotesMarkdown.blocks("\n\n"), [])
        XCTAssertEqual(NotesMarkdown.blocks("#### Deep"), [.heading(level: 3, text: "Deep")])
        XCTAssertEqual(NotesMarkdown.blocks("> one\n\n> two"), [.quote("one"), .quote("two")])
        XCTAssertEqual(NotesMarkdown.blocks("```\nunclosed"), [.code("unclosed")])
        XCTAssertEqual(NotesMarkdown.blocks("2026. A year"), [.numbered(number: 2026, text: "A year", indent: 0)])
        XCTAssertEqual(NotesMarkdown.blocks("12345. Not a list"), [.paragraph("12345. Not a list")])
    }

    // MARK: Gallery

    func testGalleryIndex() {
        XCTAssertEqual(GalleryIndex.step(0, by: -1, count: 3), 0, "stops at the first")
        XCTAssertEqual(GalleryIndex.step(0, by: 1, count: 3), 1)
        XCTAssertEqual(GalleryIndex.step(2, by: 1, count: 3), 2, "stops at the last")
        XCTAssertEqual(GalleryIndex.step(5, by: 0, count: 3), 2, "an index past the end is pulled back")
        XCTAssertEqual(GalleryIndex.step(0, by: 1, count: 0), 0)
        XCTAssertEqual(GalleryIndex.afterRemoving(at: 1, count: 3), 1, "the next one moves into place")
        XCTAssertEqual(GalleryIndex.afterRemoving(at: 2, count: 3), 1, "the last one falls back")
        XCTAssertNil(GalleryIndex.afterRemoving(at: 0, count: 1))
        XCTAssertEqual(GalleryIndex.label(1, count: 5), "2 of 5")
    }
}
