import XCTest

/// Two-way sync: Calendar edits pulled into tasks, the conflict rule, deletions. Pure logic, no EventKit.
final class TwoWaySyncTests: XCTestCase {
    private let cal = Calendar.current
    private let today = "2026-10-05"
    private var todayDate: Date { DayKey.date(from: today, calendar: cal)! }
    private func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: todayDate)! }
    private let synced = Date(timeIntervalSince1970: 1_790_000_000)

    private func info(_ f: (inout EventTaskInfo) -> Void = { _ in }) -> EventTaskInfo {
        var i = EventTaskInfo(title: "Pay rent", notes: "", dueDate: day(1), hasDueTime: false, priority: .medium,
                              estimateMinutes: nil, isCompleted: false, topSlot: nil, topDay: nil)
        f(&i)
        return i
    }

    private func due(_ i: EventTaskInfo) -> EventSpec { EventPlanner.specs(for: i, today: today, calendar: cal)[.due]! }

    /// The link as it is right after ProTask pushed `spec`.
    private func link(for spec: EventSpec) -> LinkState {
        LinkState(kind: spec.kind, contentHash: spec.fingerprint, remoteModifiedAt: synced, lastSyncedAt: synced)
    }

    private func remote(_ spec: EventSpec, modified: Date? = nil, _ f: (inout RemoteState) -> Void = { _ in }) -> RemoteState {
        var r = RemoteState(title: spec.title, start: spec.start, end: spec.end, isAllDay: spec.isAllDay, lastModified: modified ?? synced)
        f(&r)
        return r
    }

    // MARK: Remote edit pulled in

    func testRemoteEditOfTitleAndDateIsPulledIntoTheTask() {
        let task = info()
        let spec = due(task)
        let edited = remote(spec, modified: synced + 60) { $0.title = "Pay rent and bills"; $0.start = self.day(3); $0.end = self.day(3) }
        XCTAssertEqual(LinkSync.pull(link: link(for: spec), remote: edited, local: spec, localModified: nil), .pull)

        let patch = LinkSync.remotePatch(kind: .due, remote: edited, task: task, pinDay: nil, calendar: cal)
        XCTAssertEqual(patch.title, "Pay rent and bills")
        XCTAssertEqual(patch.dueDate, day(3))
        XCTAssertEqual(patch.hasDueTime, false)
        XCTAssertNil(patch.estimateMinutes)
        XCTAssertFalse(patch.pinnedMoved)
    }

    func testRemoteMoveAndResizeOfATimedEventSetsTimeAndEstimate() {
        let start = day(1).addingTimeInterval(9 * 3600)
        let task = info { $0.dueDate = start; $0.hasDueTime = true }
        let spec = due(task)
        let moved = start.addingTimeInterval(2 * 3600)
        let edited = remote(spec) { $0.start = moved; $0.end = moved.addingTimeInterval(90 * 60) }
        let patch = LinkSync.remotePatch(kind: .due, remote: edited, task: task, pinDay: nil, calendar: cal)
        XCTAssertEqual(patch.dueDate, moved)
        XCTAssertEqual(patch.hasDueTime, true)
        XCTAssertEqual(patch.estimateMinutes, 90)
    }

    func testDoneMarkIsNotPulledIntoTheTitle() {
        let task = info { $0.isCompleted = true }
        let spec = due(task)
        XCTAssertTrue(spec.title.hasPrefix(EventPlanner.doneMark))
        let patch = LinkSync.remotePatch(kind: .due, remote: remote(spec), task: task, pinDay: nil, calendar: cal)
        XCTAssertFalse(patch.changesTask)
        XCTAssertEqual(LinkSync.cleanTitle("✓ Pay rent  "), "Pay rent")
    }

    // MARK: Local edit pushed out

    func testLocalEditIsPushedAndNotMistakenForACalendarEdit() {
        let before = due(info())
        let after = due(info { $0.title = "Pay rent early" })
        // Calendar still has what we last pushed: nothing to pull, the push updates the event.
        XCTAssertEqual(LinkSync.pull(link: link(for: before), remote: remote(before), local: after, localModified: Date()), .unchanged)
        XCTAssertEqual(LinkSync.push(specs: [.due: after], links: [.due: link(for: before)], remoteMatches: [.due: false]), [.due: .update])
    }

    func testOwnWriteIsUnchangedAndConvergedEditsNeedNoConflict() {
        let spec = due(info())
        XCTAssertEqual(LinkSync.pull(link: link(for: spec), remote: remote(spec, modified: synced + 5), local: spec, localModified: nil), .unchanged)
        let both = due(info { $0.title = "Same new title" })
        XCTAssertEqual(LinkSync.pull(link: link(for: spec), remote: remote(both), local: both, localModified: Date()), .converged)
    }

    func testLinkWithoutBaselineIsLeftToThePush() {
        let spec = due(info())
        var legacy = link(for: spec)
        legacy.contentHash = nil
        XCTAssertEqual(LinkSync.pull(link: legacy, remote: remote(spec) { $0.title = "Other" }, local: spec, localModified: nil), .unchanged)
    }

    // MARK: Both edited (conflict)

    func testConflictCalendarNewerWins() {
        let spec = due(info())
        let local = due(info { $0.title = "ProTask title" })
        let edited = remote(spec, modified: synced + 600) { $0.title = "Calendar title" }
        XCTAssertEqual(LinkSync.pull(link: link(for: spec), remote: edited, local: local, localModified: synced + 60), .remoteWins)
    }

    func testConflictProTaskNewerWins() {
        let spec = due(info())
        let local = due(info { $0.title = "ProTask title" })
        let edited = remote(spec, modified: synced + 60) { $0.title = "Calendar title" }
        XCTAssertEqual(LinkSync.pull(link: link(for: spec), remote: edited, local: local, localModified: synced + 600), .localWins)
    }

    func testConflictWithoutALocalEditTimeFallsBackToTheLastSync() {
        let spec = due(info())
        let local = due(info { $0.title = "ProTask title" })
        let edited = remote(spec, modified: synced + 1) { $0.title = "Calendar title" }
        XCTAssertEqual(LinkSync.pull(link: link(for: spec), remote: edited, local: local, localModified: nil), .remoteWins)
    }

    // MARK: Remote delete

    func testRemoteDeleteMarksTheTaskUnscheduledAndItGetsNoEvents() {
        let task = info { $0.topSlot = 1; $0.topDay = self.today }
        let specs = EventPlanner.specs(for: task, today: today, calendar: cal)
        XCTAssertEqual(LinkSync.pull(link: link(for: specs[.due]!), remote: nil, local: specs[.due], localModified: nil), .deleted)

        var off = task
        off.unscheduled = true
        let none = EventPlanner.specs(for: off, today: today, calendar: cal)
        XCTAssertTrue(none.isEmpty, "no event is recreated until it's rescheduled")
        // The remaining pinned link is removed; the task itself is untouched.
        XCTAssertEqual(LinkSync.push(specs: none, links: [.pinned: link(for: specs[.pinned]!)], remoteMatches: [:]), [.pinned: .remove])
    }

    func testEveryEventMissingAtOnceIsNotTreatedAsDeletion() {
        XCTAssertTrue(LinkSync.trustMissing(missing: 1, total: 5))
        XCTAssertTrue(LinkSync.trustMissing(missing: 2, total: 2), "a couple of deliberate deletes still count")
        XCTAssertFalse(LinkSync.trustMissing(missing: 3, total: 3), "calendar replaced or not loaded")
        XCTAssertFalse(LinkSync.trustMissing(missing: 40, total: 40))
    }

    // MARK: Pinned events

    func testMovingATop3EventPullsOnlyTheTitleAndReportsTheMove() {
        let task = info { $0.dueDate = nil; $0.topSlot = 1; $0.topDay = self.today }
        let pinned = EventPlanner.specs(for: task, today: today, calendar: cal)[.pinned]!
        let edited = remote(pinned) { $0.title = "Pay rent now"; $0.start = self.day(2); $0.end = self.day(2) }
        let patch = LinkSync.remotePatch(kind: .pinned, remote: edited, task: task, pinDay: todayDate, calendar: cal)
        XCTAssertEqual(patch.title, "Pay rent now")
        XCTAssertNil(patch.dueDate)
        XCTAssertTrue(patch.pinnedMoved)
    }
}
