import XCTest

private struct T: SortableTask {
    var name: String
    var dueDate: Date? = nil
    var hasDueTime = false
    var priority: Priority = .medium
    var estimateMinutes: Int? = nil
    var position: Double
}

final class TaskSortingTests: XCTestCase {
    private let cal = Calendar.current
    private func day(_ d: Int, _ h: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h))! }
    private func names(_ ts: [T]) -> [String] { TaskSorting.sorted(ts, calendar: cal).map(\.name) }

    func testSoonestDueFirstAndUndatedLast() {
        let ts = [T(name: "none", position: 1), T(name: "later", dueDate: day(10), position: 2), T(name: "sooner", dueDate: day(6), position: 3)]
        XCTAssertEqual(names(ts), ["sooner", "later", "none"])
    }

    func testPriorityBreaksDueTies() {
        let ts = [T(name: "low", dueDate: day(6), priority: .low, position: 1),
                  T(name: "high", dueDate: day(6), priority: .high, position: 2),
                  T(name: "med", dueDate: day(6), position: 3)]
        XCTAssertEqual(names(ts), ["high", "med", "low"])
    }

    func testShortestEstimateBreaksPriorityTies() {
        let ts = [T(name: "none", position: 1), T(name: "long", estimateMinutes: 90, position: 2), T(name: "short", estimateMinutes: 10, position: 3)]
        XCTAssertEqual(names(ts), ["short", "long", "none"])
    }

    func testDueDateOutranksPriorityAndEstimate() {
        let ts = [T(name: "high-undated-short", priority: .high, estimateMinutes: 5, position: 1),
                  T(name: "low-due", dueDate: day(7), priority: .low, estimateMinutes: 120, position: 2)]
        XCTAssertEqual(names(ts), ["low-due", "high-undated-short"])
    }

    func testTimedTaskBeforeDateOnlyTaskSameDay() {
        let ts = [T(name: "all-day", dueDate: day(6), position: 1), T(name: "3pm", dueDate: day(6, 15), hasDueTime: true, position: 2)]
        XCTAssertEqual(names(ts), ["3pm", "all-day"])
    }

    func testFullTiesKeepManualOrder() {
        let ts = [T(name: "c", position: 3), T(name: "a", position: 1), T(name: "b", position: 2)]
        XCTAssertEqual(names(ts), ["a", "b", "c"])
    }
}
