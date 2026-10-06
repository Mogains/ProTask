import XCTest

/// The text copied for AI chat: section toggles, truncation, prompts and the reply format.
final class ChatSnapshotTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()
    private var today: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 5))! }
    private func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private var input: ChatSnapshot.Input {
        ChatSnapshot.Input(
            today: today,
            top3: [1: .init(title: "Finish report", dueDate: at(5, 15), hasDueTime: true, priority: .high, estimateMinutes: 90),
                   2: .init(title: "Pay rent", isCompleted: true)],
            haveTo: [.init(title: "Book dentist", notes: "Ask about the\nnew insurance card and whether they take it, and also check the parking situation near the office", dueDate: at(8))],
            niceTo: [.init(title: "Read two chapters", priority: .low, estimateMinutes: 40)],
            waiting: [.init(title: "Contract redlines", waitingOn: "Legal", followUpDate: at(6))],
            ideas: [.init(title: "Try the new ramen place")],
            events: [.init(title: "Standup", start: at(5, 9), end: at(5, 9, 15), isAllDay: false),
                     .init(title: "Holiday", start: at(5), end: at(6), isAllDay: true)])
    }

    private func build(_ f: (inout ChatSnapshot.Sections) -> Void = { _ in }, prompt: ChatPrompt? = nil) -> String {
        var s = ChatSnapshot.Sections()
        f(&s)
        return ChatSnapshot.build(input, sections: s, prompt: prompt, calendar: cal)
    }

    func testEverythingIncludedByDefault() {
        let text = build()
        XCTAssertTrue(text.hasPrefix("ProTask snapshot for Monday 2026-10-05"))
        XCTAssertTrue(text.contains("1. Finish report (due 2026-10-05 15:00, high priority, 90 min)"))
        XCTAssertTrue(text.contains("2. [done] Pay rent"))
        XCTAssertTrue(text.contains("3. (empty)"))
        XCTAssertTrue(text.contains("Have to do:\n- Book dentist (due 2026-10-08)"))
        XCTAssertTrue(text.contains("- Read two chapters (low priority, 40 min)"))
        XCTAssertTrue(text.contains("Waiting On:\n- Contract redlines, waiting on Legal, follow up 2026-10-06"))
        XCTAssertTrue(text.contains("Parking Lot:\n- Try the new ramen place"))
        XCTAssertTrue(text.contains("- 09:00 to 09:15 Standup"))
        XCTAssertTrue(text.contains("- all day Holiday"))
        XCTAssertTrue(text.contains("```protask-actions"), "every copy asks for the reply format")
    }

    func testEachSectionToggleRemovesOnlyThatSection() {
        XCTAssertFalse(build { $0.top3 = false }.contains("Top 3 today:"))
        let noLists = build { $0.lists = false }
        XCTAssertFalse(noLists.contains("Have to do:\n"))
        XCTAssertFalse(noLists.contains("Nice to do:\n"))
        XCTAssertTrue(noLists.contains("Top 3 today:"))
        XCTAssertFalse(build { $0.waiting = false }.contains("Waiting On:"))
        XCTAssertFalse(build { $0.ideas = false }.contains("Try the new ramen place"))
        let noEvents = build { $0.events = false }
        XCTAssertFalse(noEvents.contains("Standup"))
        XCTAssertTrue(noEvents.contains("Parking Lot:"))
    }

    func testNotesAreShortenedToOneLineAndCanBeLeftOut() {
        let text = build()
        let line = text.components(separatedBy: "\n").first { $0.contains("Book dentist") }!
        XCTAssertTrue(line.contains("Notes: Ask about the new insurance card"), "newlines are folded")
        let notes = line.components(separatedBy: "Notes: ")[1]
        XCTAssertLessThanOrEqual(notes.count, ChatSnapshot.noteLimit)
        XCTAssertTrue(notes.hasSuffix("…"))
        XCTAssertFalse(build { $0.notes = false }.contains("insurance"))
    }

    func testLongTitlesAreTruncated() {
        let long = String(repeating: "a", count: 500)
        XCTAssertEqual(ChatSnapshot.clean(long, limit: ChatSnapshot.titleLimit).count, ChatSnapshot.titleLimit)
        XCTAssertEqual(ChatSnapshot.clean("  short  ", limit: 10), "short")
    }

    func testEmptyWaitingOnIsOmittedButEmptyListsSayNone() {
        var i = input
        i.waiting = []
        i.ideas = []
        let text = ChatSnapshot.build(i, sections: .init(), calendar: cal)
        XCTAssertFalse(text.contains("Waiting On:"))
        XCTAssertTrue(text.contains("Parking Lot:\n(none)"))
    }

    func testPromptChipAddsItsInstruction() {
        for p in ChatPrompt.allCases {
            let text = build(prompt: p)
            XCTAssertTrue(text.contains(p.instruction))
            XCTAssertTrue(text.contains("Top 3 today:"))
        }
        XCTAssertFalse(build().contains(ChatPrompt.planDay.instruction))
    }
}
