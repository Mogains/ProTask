import XCTest

/// Multiple events per task: due (or series) and pinned, planned per slot.
final class EventLinkTests: XCTestCase {
    private let cal = Calendar.current
    private let today = "2026-10-05"
    private var todayDate: Date { DayKey.date(from: today, calendar: cal)! }
    private var tomorrow: Date { cal.date(byAdding: .day, value: 1, to: todayDate)! }

    private func info(_ f: (inout EventTaskInfo) -> Void = { _ in }) -> EventTaskInfo {
        var i = EventTaskInfo(title: "Pay rent", notes: "", dueDate: nil, hasDueTime: false, priority: .medium,
                              estimateMinutes: nil, isCompleted: false, topSlot: nil, topDay: nil)
        f(&i)
        return i
    }

    private func specs(_ i: EventTaskInfo) -> [LinkSlot: EventSpec] { EventPlanner.specs(for: i, today: today, calendar: cal) }
    private func linked(_ s: [LinkSlot: EventSpec]) -> [LinkSlot: LinkState] {
        s.mapValues { LinkState(kind: $0.kind, contentHash: $0.fingerprint) }
    }

    func testPinDueTomorrowAddsPinnedEventTodayAndKeepsDueEvent() {
        let due = info { $0.dueDate = self.tomorrow }
        let before = specs(due)
        XCTAssertEqual(Set(before.keys), [.due])

        let pinned = specs(info { $0.dueDate = self.tomorrow; $0.topSlot = 1; $0.topDay = self.today })
        XCTAssertEqual(Set(pinned.keys), [.due, .pinned])
        XCTAssertEqual(pinned[.due]?.start, tomorrow)
        XCTAssertEqual(pinned[.pinned]?.start, todayDate)
        XCTAssertTrue(pinned[.pinned]!.isAllDay)
        XCTAssertEqual(pinned[.due]?.fingerprint, before[.due]?.fingerprint, "the due event is untouched by pinning")

        let plan = LinkSync.push(specs: pinned, links: linked(before), remoteMatches: [.due: true])
        XCTAssertEqual(plan, [.due: .keep, .pinned: .create])
    }

    func testPinOnTheDueDayMakesOneEvent() {
        let s = specs(info { $0.dueDate = self.todayDate; $0.topSlot = 2; $0.topDay = self.today })
        XCTAssertEqual(Set(s.keys), [.due])
        XCTAssertTrue(s[.due]!.notes.contains("Today's Top 3, #2"))
    }

    func testUnpinRemovesOnlyThePinnedEvent() {
        let pinned = specs(info { $0.dueDate = self.tomorrow; $0.topSlot = 1; $0.topDay = self.today })
        let unpinned = specs(info { $0.dueDate = self.tomorrow })
        let plan = LinkSync.push(specs: unpinned, links: linked(pinned), remoteMatches: [.due: true, .pinned: false])
        XCTAssertEqual(plan, [.due: .keep, .pinned: .remove])
    }

    func testMoveUpdatesTheDueEventOnly() {
        let pinned = specs(info { $0.dueDate = self.tomorrow; $0.topSlot = 1; $0.topDay = self.today })
        let later = cal.date(byAdding: .day, value: 3, to: todayDate)!
        let moved = specs(info { $0.dueDate = later; $0.topSlot = 1; $0.topDay = self.today })
        XCTAssertEqual(moved[.due]?.start, later)
        XCTAssertEqual(moved[.pinned]?.start, todayDate)
        // The existing due event no longer matches the spec; the pinned one still does.
        let plan = LinkSync.push(specs: moved, links: linked(pinned), remoteMatches: [.due: false, .pinned: true])
        XCTAssertEqual(plan, [.due: .update, .pinned: .keep])
    }

    func testCompleteMarksEveryEventDone() {
        let done = specs(info { $0.dueDate = self.tomorrow; $0.topSlot = 1; $0.topDay = self.today; $0.isCompleted = true })
        XCTAssertEqual(done[.due]?.title, "✓ Pay rent")
        XCTAssertEqual(done[.pinned]?.title, "✓ Pay rent")
        let open = specs(info { $0.dueDate = self.tomorrow; $0.topSlot = 1; $0.topDay = self.today })
        let plan = LinkSync.push(specs: done, links: linked(open), remoteMatches: [.due: false, .pinned: false])
        XCTAssertEqual(plan, [.due: .update, .pinned: .update])
    }

    func testDeleteRemovesEveryEvent() {
        let s = specs(info { $0.dueDate = self.tomorrow; $0.topSlot = 1; $0.topDay = self.today })
        XCTAssertEqual(LinkSync.deleteTask(links: linked(s)), [.due: .remove, .pinned: .remove])
    }

    func testRecurringTaskIsASeriesUntilFinished() {
        let rule = RecurrenceRule(kind: .weekly)
        let open = specs(info { $0.dueDate = self.tomorrow; $0.recurrence = rule })
        XCTAssertEqual(open[.due]?.kind, .series)
        XCTAssertNotNil(open[.due]?.recurrence)
        // Finishing the occurrence keeps the same slot; its event becomes a single due event.
        let done = specs(info { $0.dueDate = self.tomorrow; $0.recurrence = rule; $0.isCompleted = true })
        XCTAssertEqual(done[.due]?.kind, .due)
        XCTAssertNil(done[.due]?.recurrence)
        XCTAssertEqual(LinkKind.series.slot, LinkKind.due.slot)
    }

    func testFingerprintIgnoresTimeOfDayForAllDayEventsButNotForTimed() {
        let a = EventFingerprint.make(title: "X", start: todayDate, end: todayDate, isAllDay: true, calendar: cal)
        let b = EventFingerprint.make(title: "X", start: todayDate.addingTimeInterval(3600), end: todayDate, isAllDay: true, calendar: cal)
        XCTAssertEqual(a, b)
        let t1 = EventFingerprint.make(title: "X", start: todayDate, end: todayDate.addingTimeInterval(1800), isAllDay: false, calendar: cal)
        let t2 = EventFingerprint.make(title: "X", start: todayDate.addingTimeInterval(60), end: todayDate.addingTimeInterval(1860), isAllDay: false, calendar: cal)
        XCTAssertNotEqual(t1, t2)
        XCTAssertNotEqual(a, EventFingerprint.make(title: "Y", start: todayDate, end: todayDate, isAllDay: true, calendar: cal))
    }
}
