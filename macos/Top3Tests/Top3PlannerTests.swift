import XCTest

final class Top3PlannerTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()
    private var full: [Top3Planner.Occupant] {
        [.init(slot: 1, taskID: a), .init(slot: 2, taskID: b), .init(slot: 3, taskID: c)]
    }

    func testStarFillsFirstFreeSlot() {
        XCTAssertEqual(Top3Planner.plan(occupants: [], taskID: d), .assign(slot: 1, displaced: nil))
        XCTAssertEqual(Top3Planner.plan(occupants: [.init(slot: 1, taskID: a), .init(slot: 3, taskID: c)], taskID: d),
                       .assign(slot: 2, displaced: nil))
    }

    func testFourthTaskIsRefused() {
        XCTAssertEqual(Top3Planner.plan(occupants: full, taskID: d), .full)
    }

    func testNeverMoreThanThree() {
        var occ: [Top3Planner.Occupant] = []
        for id in [a, b, c, d, e] {
            occ = Top3Planner.apply(Top3Planner.plan(occupants: occ, taskID: id), to: occ, taskID: id)
        }
        XCTAssertEqual(occ.map(\.taskID), [a, b, c])
        for (id, slot) in [(d, 2), (e, 1), (a, 3), (b, 3)] {
            occ = Top3Planner.apply(Top3Planner.plan(occupants: occ, taskID: id, requested: slot), to: occ, taskID: id)
            XCTAssertLessThanOrEqual(occ.count, 3)
            XCTAssertEqual(Set(occ.map(\.slot)).count, occ.count, "two tasks share a slot")
            XCTAssertEqual(Set(occ.map(\.taskID)).count, occ.count, "a task is in two slots")
        }
    }

    func testStarringPinnedTaskKeepsSlot() {
        XCTAssertEqual(Top3Planner.plan(occupants: full, taskID: b), .assign(slot: 2, displaced: nil))
    }

    func testOccupiedSlotSendsOldTaskBack() {
        let plan = Top3Planner.plan(occupants: full, taskID: d, requested: 2)
        XCTAssertEqual(plan, .assign(slot: 2, displaced: .init(taskID: b, toSlot: nil)))
        XCTAssertEqual(Top3Planner.apply(plan, to: full, taskID: d).map(\.taskID), [a, d, c])
    }

    func testMovingBetweenSlotsSwaps() {
        let plan = Top3Planner.plan(occupants: full, taskID: a, requested: 3)
        XCTAssertEqual(plan, .assign(slot: 3, displaced: .init(taskID: c, toSlot: 1)))
        XCTAssertEqual(Top3Planner.apply(plan, to: full, taskID: a).map(\.taskID), [c, b, a])
    }

    func testInvalidSlots() {
        XCTAssertEqual(Top3Planner.plan(occupants: [], taskID: d, requested: 0), .invalidSlot)
        XCTAssertEqual(Top3Planner.plan(occupants: [], taskID: d, requested: 4), .invalidSlot)
    }
}

final class CaptureRoutingTests: XCTestCase {
    func testPrefixesPickTheList() {
        XCTAssertEqual(CaptureRouting.route("buy milk").list, .haveTo)
        XCTAssertEqual(CaptureRouting.route("~ read a novel").list, .niceTo)
        XCTAssertEqual(CaptureRouting.route("~ read a novel").text, "read a novel")
        XCTAssertEqual(CaptureRouting.route("?idea").list, .parkingLot)
        XCTAssertEqual(CaptureRouting.route("?idea").text, "idea")
        XCTAssertEqual(CaptureRouting.route("  ~x").list, .niceTo)
    }
}
