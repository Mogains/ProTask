import XCTest

final class RolloverTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()

    func testOldPinsAreClearedAndUnfinishedRollOver() {
        let pins = [Rollover.Pin(id: a, topDay: "2026-10-04", isCompleted: false),
                    Rollover.Pin(id: b, topDay: "2026-10-04", isCompleted: true),
                    Rollover.Pin(id: c, topDay: "2026-10-05", isCompleted: false)]
        let r = Rollover.plan(pins: pins, today: "2026-10-05")
        XCTAssertEqual(Set(r.unpin), [a, b])
        XCTAssertEqual(r.rolledOver, [a])
    }

    func testNothingHappensOnTheSameDay() {
        let r = Rollover.plan(pins: [Rollover.Pin(id: a, topDay: "2026-10-05", isCompleted: false)], today: "2026-10-05")
        XCTAssertEqual(r, Rollover.Result(unpin: [], rolledOver: []))
    }

    func testPinWithoutDayIsStale() {
        XCTAssertEqual(Rollover.plan(pins: [Rollover.Pin(id: a, topDay: nil, isCompleted: false)], today: "2026-10-05").rolledOver, [a])
    }

    func testClosingTheDayRollsOverOnlyUnfinished() {
        let r = Rollover.closeDay(pins: [Rollover.Pin(id: a, topDay: "2026-10-05", isCompleted: false),
                                         Rollover.Pin(id: b, topDay: "2026-10-05", isCompleted: true)])
        XCTAssertEqual(r.unpin, [a])
        XCTAssertEqual(r.rolledOver, [a])
    }

    func testIDListRoundTrip() {
        XCTAssertEqual(Rollover.decode(Rollover.encode([a, b])), [a, b])
        XCTAssertEqual(Rollover.decode(""), [])
    }
}
