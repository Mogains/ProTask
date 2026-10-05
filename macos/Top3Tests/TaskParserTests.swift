import XCTest

final class TaskParserTests: XCTestCase {
    private let cal = Calendar.current
    /// Monday, October 5 2026, 10:00.
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10))!

    func testDateAndTimeAreExtracted() {
        let p = TaskParser.parse("email prof friday 3pm", now: now, calendar: cal)
        XCTAssertEqual(p.title, "email prof")
        XCTAssertTrue(p.hasDueTime)
        XCTAssertEqual(cal.component(.weekday, from: p.dueDate!), 6) // Friday
        XCTAssertEqual(cal.component(.hour, from: p.dueDate!), 15)
        XCTAssertEqual(p.datePhrase?.lowercased(), "friday 3pm")
        XCTAssertTrue(p.dateAtEnd)
    }

    func testDateWithoutTimeIsAllDay() {
        let p = TaskParser.parse("pay rent tomorrow", now: now, calendar: cal)
        XCTAssertEqual(p.title, "pay rent")
        XCTAssertFalse(p.hasDueTime)
        XCTAssertEqual(p.dueDate, cal.startOfDay(for: p.dueDate!))
    }

    func testPriorityMarks() {
        XCTAssertEqual(TaskParser.parse("ship it !!!", now: now).priority, .high)
        XCTAssertEqual(TaskParser.parse("ship it !!", now: now).priority, .medium)
        XCTAssertEqual(TaskParser.parse("ship it !", now: now).priority, .low)
        XCTAssertEqual(TaskParser.parse("ship it !!!", now: now).title, "ship it")
        XCTAssertNil(TaskParser.parse("wow!", now: now).priority, "a ! attached to a word is punctuation")
    }

    func testEstimates() {
        XCTAssertEqual(TaskParser.parse("review PR 30m", now: now).estimateMinutes, 30)
        XCTAssertEqual(TaskParser.parse("deep work 1h", now: now).estimateMinutes, 60)
        XCTAssertEqual(TaskParser.parse("deep work 1.5h", now: now).estimateMinutes, 90)
        XCTAssertEqual(TaskParser.parse("deep work 1h30m", now: now).estimateMinutes, 90)
        XCTAssertEqual(TaskParser.parse("call 45 min", now: now).estimateMinutes, 45)
        XCTAssertEqual(TaskParser.parse("review PR 30m", now: now).title, "review PR")
    }

    func testEverythingTogether() {
        let p = TaskParser.parse("draft proposal tomorrow 9am !!! 1h", now: now, calendar: cal)
        XCTAssertEqual(p.title, "draft proposal")
        XCTAssertEqual(p.priority, .high)
        XCTAssertEqual(p.estimateMinutes, 60)
        XCTAssertEqual(cal.component(.hour, from: p.dueDate!), 9)
    }

    func testIgnoredPhraseStaysInTitle() {
        let p = TaskParser.parse("email prof friday 3pm", now: now, calendar: cal, ignoring: "friday 3pm")
        XCTAssertNil(p.dueDate)
        XCTAssertEqual(p.title, "email prof friday 3pm")
    }

    func testPlainTitleIsUntouched() {
        let p = TaskParser.parse("Buy oat milk", now: now, calendar: cal)
        XCTAssertEqual(p.title, "Buy oat milk")
        XCTAssertFalse(p.hasExtras)
    }

    func testTagsAreExtracted() {
        let p = TaskParser.parse("plan offsite #Work #team-q4 tomorrow", now: now, calendar: cal)
        XCTAssertEqual(p.tags, ["work", "team-q4"])
        XCTAssertEqual(p.title, "plan offsite")
        XCTAssertNotNil(p.dueDate)
        XCTAssertEqual(TaskParser.parse("issue #42 fix", now: now).tags, ["42"])
        XCTAssertEqual(TaskParser.parse("C# notes", now: now).tags, [], "a # inside a word is not a tag")
    }

    func testDanglingConnectorIsRemoved() {
        XCTAssertEqual(TaskParser.parse("call mom at 6pm", now: now, calendar: cal).title, "call mom")
    }
}

final class FuzzyTests: XCTestCase {
    func testSubsequenceMatches() {
        XCTAssertNotNil(Fuzzy.score("nt", in: "New task"))
        XCTAssertNil(Fuzzy.score("xyz", in: "New task"))
        XCTAssertEqual(Fuzzy.score("", in: "anything"), 0)
    }

    func testWordStartsAndPrefixesRankHigher() {
        let a = Fuzzy.score("gt", in: "Go to Today")!
        let b = Fuzzy.score("gt", in: "Big thing")!
        XCTAssertGreaterThan(a, b)
        XCTAssertGreaterThan(Fuzzy.score("new", in: "New idea")!, Fuzzy.score("new", in: "Renew passport")!)
    }
}
