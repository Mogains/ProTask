import XCTest

final class BackupTests: XCTestCase {
    private func task(_ title: String, list: ListKind = .haveTo, done: Bool = false, slot: Int? = nil, tags: String = "") -> BackupFile.TaskDTO {
        .init(id: UUID(), title: title, notes: "", dueDate: nil, hasDueTime: false, priorityRaw: 1, estimateMinutes: nil,
              isCompleted: done, completedAt: done ? Date() : nil, listRaw: list.rawValue, position: 0, topSlot: slot, topDay: nil,
              calendarEventID: nil, createdAt: Date(timeIntervalSince1970: (Date().timeIntervalSince1970 * 1000).rounded() / 1000), remindAt: nil, recurrenceRaw: nil, seriesID: nil, nextOccurrenceID: nil,
              actualSeconds: 0, waitingOn: "", followUpDate: nil, tagsRaw: tags)
    }

    func testJSONRoundTrip() throws {
        let file = BackupFile(exportedAt: Date(timeIntervalSince1970: 1_800_000_000), tasks: [task("a", tags: "work")],
                              dayLogs: [.init(day: "2026-10-05", top3Complete: true, promptDismissed: false, planningDone: true, dayClosed: false, rolledOverRaw: "")],
                              listSettings: [.init(listRaw: "haveTo", autoSort: false)],
                              focusSessions: [.init(id: UUID(), taskID: nil, taskTitle: "x", start: Date(timeIntervalSince1970: 1_800_000_000), seconds: 1500)])
        XCTAssertEqual(try BackupFile.decode(file.encoded()), file)
    }

    func testRejectsOtherFiles() {
        XCTAssertThrowsError(try BackupFile.decode(Data(#"{"format":"other","version":1,"exportedAt":"2026-10-05T00:00:00Z","tasks":[],"dayLogs":[],"listSettings":[],"focusSessions":[]}"#.utf8)))
    }

    func testMarkdownGroupsByList() {
        let md = MarkdownExport.render([task("Pinned", slot: 1), task("Errand", tags: "home"), task("Novel", list: .niceTo),
                                        task("Idea", list: .parkingLot), task("Shipped", done: true)])
        XCTAssertTrue(md.contains("## Top 3\n\n- [ ] Pinned"))
        XCTAssertTrue(md.contains("## Have to do\n\n- [ ] Errand — #home"))
        XCTAssertTrue(md.contains("## Nice to do\n\n- [ ] Novel"))
        XCTAssertTrue(md.contains("## Parking Lot\n\n- Idea"))
        XCTAssertTrue(md.contains("- [x] Shipped"))
        XCTAssertFalse(md.contains("## Waiting On"), "empty sections are left out")
    }

    func testRotationKeepsNewestSeven() {
        let names = (1...10).map { BackupRotation.fileName(for: String(format: "2026-10-%02d", $0)) } + ["ProTask-before-import-1.json", "notes.txt"]
        let doomed = BackupRotation.toDelete(names)
        XCTAssertEqual(doomed, ["ProTask-2026-10-03.json", "ProTask-2026-10-02.json", "ProTask-2026-10-01.json"])
    }
}
