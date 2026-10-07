import XCTest

final class VisionModelTests: XCTestCase {
    // MARK: Metric math

    func testIncreasingMetric() {
        let m = GoalMetric(name: "Long run", start: 5, current: 12, target: 21.1, unit: "km")
        XCTAssertFalse(m.isDecreasing)
        XCTAssertEqual(m.fraction, 7 / 16.1, accuracy: 1e-9)
        XCTAssertEqual(m.percent, 43)
        XCTAssertEqual(m.remaining, 9.1, accuracy: 1e-9)
        XCTAssertFalse(m.isReached)
    }

    func testDecreasingMetric() {
        let loan = GoalMetric(name: "Balance", start: 14_000, current: 8_600, target: 0, unit: "USD")
        XCTAssertTrue(loan.isDecreasing)
        XCTAssertEqual(loan.fraction, 5_400 / 14_000, accuracy: 1e-9)
        XCTAssertEqual(loan.percent, 39)
        XCTAssertEqual(loan.remaining, 8_600)

        XCTAssertEqual(GoalProgress.metricFraction(start: 90, current: 85, target: 80), 0.5)
        XCTAssertEqual(GoalProgress.metricFraction(start: 90, current: 80, target: 80), 1)
        XCTAssertEqual(GoalProgress.metricFraction(start: 90, current: 78, target: 80), 1, "passing a decreasing target counts as done")
        XCTAssertEqual(GoalProgress.metricFraction(start: 90, current: 92, target: 80), 0, "moving away from the target counts as 0")
        XCTAssertTrue(GoalMetric(name: "", start: 90, current: 78, target: 80).isReached)
        XCTAssertEqual(GoalMetric(name: "", start: 90, current: 78, target: 80).remaining, 0)
    }

    func testMetricEdgeCases() {
        XCTAssertEqual(GoalProgress.metricFraction(start: 0, current: 120, target: 100), 1, "overshoot clamps to 1")
        XCTAssertEqual(GoalProgress.metricFraction(start: 10, current: 5, target: 100), 0, "below the start clamps to 0")
        XCTAssertEqual(GoalProgress.metricFraction(start: 50, current: 50, target: 50), 1, "a hold-steady target is met when on it")
        XCTAssertEqual(GoalProgress.metricFraction(start: 50, current: 49, target: 50), 0)
        XCTAssertEqual(GoalProgress.metricFraction(start: 0, current: .nan, target: 10), 0)
        XCTAssertEqual(GoalProgress.metricFraction(start: 0, current: 5, target: .infinity), 0)
        XCTAssertFalse(GoalMetric(name: "", start: 0, current: .nan, target: 1).isValid)
        XCTAssertEqual(GoalProgress.metricFraction(start: -10, current: -5, target: 0), 0.5, "negative ranges work")
    }

    // MARK: Progress

    func testClampingProgress() {
        XCTAssertEqual(GoalProgress.clamp(-5), 0)
        XCTAssertEqual(GoalProgress.clamp(42), 42)
        XCTAssertEqual(GoalProgress.clamp(150), 100)
        XCTAssertEqual(GoalProgress.clamp(Int.min), 0)
        XCTAssertEqual(GoalProgress.clamp(Int.max), 100)
        XCTAssertEqual(GoalProgress.clamp(99.6), 100)
        XCTAssertEqual(GoalProgress.clamp(0.4), 0)
        XCTAssertEqual(GoalProgress.clamp(42.5), 43)
        XCTAssertEqual(GoalProgress.clamp(Double.nan), 0)
        XCTAssertEqual(GoalProgress.clamp(Double.infinity), 100)
        XCTAssertEqual(GoalProgress.clamp(-Double.infinity), 0)
        XCTAssertEqual(GoalProgress.percent(0.333), 33)
    }

    func testEffectiveProgress() {
        let metric = GoalMetric(name: "Saved", start: 0, current: 2_500, target: 10_000)
        XCTAssertEqual(GoalProgress.effective(mode: .manual, manual: 30, status: .active, metric: metric), 30, "manual ignores the metric")
        XCTAssertEqual(GoalProgress.effective(mode: .manual, manual: 130, status: .active, metric: nil), 100)
        XCTAssertEqual(GoalProgress.effective(mode: .manual, manual: 30, status: .done, metric: nil), 100, "done is 100")
        XCTAssertEqual(GoalProgress.effective(mode: .auto, manual: 30, status: .active, metric: metric, linkedDone: 1, linkedTotal: 2), 25,
                       "the metric wins over linked tasks")
        XCTAssertEqual(GoalProgress.effective(mode: .auto, manual: 30, status: .active, metric: nil, linkedDone: 1, linkedTotal: 4), 25)
        XCTAssertEqual(GoalProgress.effective(mode: .auto, manual: 30, status: .active, metric: nil, linkedDone: 9, linkedTotal: 4), 100)
        XCTAssertEqual(GoalProgress.effective(mode: .auto, manual: 30, status: .planned, metric: nil), 30, "nothing to measure: the set value")
        XCTAssertEqual(GoalProgress.effective(mode: .auto, manual: 30, status: .dropped,
                                              metric: GoalMetric(name: "", start: 0, current: .nan, target: 1)), 30)
    }

    // MARK: Kinds, palette, templates

    func testStoredRawValuesAreStable() {
        // These strings are in people's databases and backups: never rename them.
        XCTAssertEqual(GoalType.allCases.map(\.rawValue), ["goal", "milestone", "habitTarget"])
        XCTAssertEqual(GoalStatus.allCases.map(\.rawValue), ["idea", "planned", "active", "done", "dropped"])
        XCTAssertEqual(ProgressMode.allCases.map(\.rawValue), ["manual", "auto"])
        XCTAssertEqual(TimelineColor.allCases.map(\.rawValue), ["slate", "mist", "sage", "sand", "clay", "rose", "plum", "stone"])
        XCTAssertEqual(GoalStatus.allCases.filter(\.isOpen), [.idea, .planned, .active])
        XCTAssertEqual(GoalType.habitTarget.title, "Habit target")
    }

    func testTimelineColors() {
        XCTAssertEqual(TimelineColor(named: "sage"), .sage)
        XCTAssertEqual(TimelineColor(named: "neon"), TimelineColor.fallback, "unknown names fall back")
        XCTAssertEqual(TimelineColor.next(after: []), .slate)
        XCTAssertEqual(TimelineColor.next(after: [.slate, .mist]), .sage)
        XCTAssertEqual(TimelineColor.next(after: TimelineColor.allCases), .slate, "cycles once all are used")
        XCTAssertEqual(TimelineColor.next(after: TimelineColor.allCases + [.slate]), .mist)
    }

    func testTemplates() {
        XCTAssertEqual(TimelineTemplate.all.map(\.name), ["Career", "Education", "Health", "Finance", "Projects", "Life"])
        XCTAssertEqual(Set(TimelineTemplate.all.map(\.id)).count, TimelineTemplate.all.count)
        XCTAssertEqual(Set(TimelineTemplate.all.map(\.color)).count, TimelineTemplate.all.count, "each template has its own color")
        XCTAssertTrue(TimelineTemplate.all.allSatisfy { !$0.details.isEmpty })
        XCTAssertEqual(TimelineTemplate.named("health")?.name, "Health")
        XCTAssertNil(TimelineTemplate.named("nope"))
        let draft = TimelineDraft(template: TimelineTemplate.named("finance")!)
        XCTAssertEqual(draft.name, "Finance")
        XCTAssertEqual(draft.color, .sand)
    }

    // MARK: Drafts and order

    func testGoalDraftNormalizes() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000), end = start.addingTimeInterval(86_400 * 30)
        var d = GoalDraft(title: "  Run a half marathon \n", notes: " notes ", timelineID: UUID(), startDate: end, targetDate: start, progress: 140,
                          metric: GoalMetric(name: " Long run ", start: 5, current: 7, target: 21, unit: " km "))
        let n = try XCTUnwrap(d.normalized())
        XCTAssertEqual(n.title, "Run a half marathon")
        XCTAssertEqual(n.notes, "notes")
        XCTAssertEqual(n.progress, 100)
        XCTAssertEqual(n.startDate, start, "a target before the start is swapped into order")
        XCTAssertEqual(n.targetDate, end)
        XCTAssertEqual(n.metric?.name, "Long run")
        XCTAssertEqual(n.metric?.unit, "km")

        d.metric = GoalMetric(name: "x", start: 0, current: .infinity, target: 1)
        XCTAssertNil(d.normalized()?.metric, "a metric with broken numbers is dropped")
        d.title = "   "
        XCTAssertNil(d.normalized())
        XCTAssertNil(TimelineDraft(name: " \n").normalized())
        XCTAssertEqual(TimelineDraft(name: " Career ", details: " Work ").normalized(), TimelineDraft(name: "Career", details: "Work"))
    }

    func testOrdering() {
        XCTAssertEqual(VisionOrder.keys(count: 3), [1000, 2000, 3000])
        XCTAssertEqual(VisionOrder.keys(count: 0), [])
        XCTAssertEqual(VisionOrder.end(after: []), 1000)
        XCTAssertEqual(VisionOrder.end(after: [500, 3000, 1000]), 4000)
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(VisionOrder.moving(c, before: a, in: [a, b, c]), [c, a, b])
        XCTAssertEqual(VisionOrder.moving(a, before: nil, in: [a, b, c]), [b, c, a])
        XCTAssertEqual(VisionOrder.moving(a, before: a, in: [a, b, c]), [a, b, c])
        XCTAssertEqual(VisionOrder.moving(a, before: UUID(), in: [a, b, c]), [b, c, a], "an unknown anchor moves to the end")
        XCTAssertEqual(VisionOrder.moving(c, before: b, in: [a, b]), [a, c, b], "a goal from another timeline is inserted")
    }

    // MARK: Dependencies

    func testDependencyCycles() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let edges = [GoalEdge(upstream: a, downstream: b), GoalEdge(upstream: b, downstream: c)]
        XCTAssertTrue(GoalGraph.wouldCreateCycle(adding: GoalEdge(upstream: a, downstream: a), to: []), "a goal can't depend on itself")
        XCTAssertTrue(GoalGraph.wouldCreateCycle(adding: GoalEdge(upstream: b, downstream: a), to: edges))
        XCTAssertTrue(GoalGraph.wouldCreateCycle(adding: GoalEdge(upstream: c, downstream: a), to: edges), "indirect loops too")
        XCTAssertFalse(GoalGraph.wouldCreateCycle(adding: GoalEdge(upstream: a, downstream: c), to: edges), "a shortcut is fine")
        XCTAssertFalse(GoalGraph.wouldCreateCycle(adding: GoalEdge(upstream: d, downstream: a), to: edges))
        XCTAssertEqual(GoalGraph.downstream(of: a, in: edges), [b, c])
        XCTAssertEqual(GoalGraph.upstream(of: c, in: edges), [a, b])
        XCTAssertEqual(GoalGraph.upstream(of: a, in: edges), [])
        // A diamond is not a loop.
        let diamond = [GoalEdge(upstream: a, downstream: b), GoalEdge(upstream: a, downstream: c), GoalEdge(upstream: b, downstream: d)]
        XCTAssertFalse(GoalGraph.wouldCreateCycle(adding: GoalEdge(upstream: c, downstream: d), to: diamond))
    }

    // MARK: Backup

    private func visionBackup() -> (BackupFile.VisionDTO, goal: UUID, image: UUID) {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let timeline = UUID(), goal = UUID(), other = UUID(), image = UUID()
        let v = BackupFile.VisionDTO(
            timelines: [.init(id: timeline, name: "Health", details: "Fitness", colorRaw: "sage", sortOrder: 1000, archived: false, createdAt: at, modifiedAt: at)],
            goals: [.init(id: goal, timelineID: timeline, title: "Run a half marathon", notes: "", typeRaw: "goal", statusRaw: "active",
                          startDate: at, targetDate: at.addingTimeInterval(86_400 * 120), progress: 40, progressModeRaw: "auto",
                          metricName: "Long run", metricStart: 5, metricCurrent: 12, metricTarget: 21.1, metricUnit: "km",
                          coverImageID: image, sortOrder: 1000, createdAt: at, modifiedAt: at, syncTargetToCalendar: false),
                    .init(id: other, timelineID: timeline, title: "Sleep", notes: "", typeRaw: "habitTarget", statusRaw: "planned",
                          startDate: nil, targetDate: nil, progress: 0, progressModeRaw: "manual", metricName: "", metricStart: nil,
                          metricCurrent: nil, metricTarget: nil, metricUnit: "", coverImageID: nil, sortOrder: 2000, createdAt: at,
                          modifiedAt: at, syncTargetToCalendar: true)],
            logs: [.init(id: UUID(), goalID: goal, date: at, text: "First 10k.", progress: 30, metricValue: 10, createdAt: at)],
            images: [.init(id: image, goalID: goal, fileName: "a.jpg", thumbnailFileName: "a-thumb.jpg", pixelWidth: 2000, pixelHeight: 1333,
                           caption: "", sortOrder: 1000, createdAt: at)],
            dependencies: [.init(id: UUID(), upstreamID: other, downstreamID: goal, createdAt: at)])
        return (v, goal, image)
    }

    func testVisionBackupRoundTrip() throws {
        let (vision, goal, _) = visionBackup()
        var task = BackupFile.TaskDTO(id: UUID(), title: "Gym", notes: "", dueDate: nil, hasDueTime: false, priorityRaw: 1, estimateMinutes: nil,
                                      isCompleted: false, completedAt: nil, listRaw: "haveTo", position: 0, topSlot: nil, topDay: nil,
                                      calendarEventID: nil, createdAt: Date(timeIntervalSince1970: 1_800_000_000), remindAt: nil,
                                      recurrenceRaw: nil, seriesID: nil, nextOccurrenceID: nil, actualSeconds: 0, waitingOn: "",
                                      followUpDate: nil, tagsRaw: "")
        task.goalID = goal
        let file = BackupFile(exportedAt: Date(timeIntervalSince1970: 1_800_000_000), tasks: [task], dayLogs: [], listSettings: [],
                              focusSessions: [], vision: vision)
        let data = try file.encoded()
        XCTAssertEqual(try BackupFile.decode(data), file)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"fileName\" : \"a.jpg\""), "images are referenced by name")
        XCTAssertEqual(vision.sanitized(), vision, "a clean backup passes through unchanged")
    }

    func testOldBackupStillImports() throws {
        let old = """
        {"format":"protask-backup","version":1,"exportedAt":"2026-10-05T00:00:00Z","dayLogs":[],"listSettings":[],"focusSessions":[],
         "tasks":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Pay rent","notes":"","hasDueTime":false,"priorityRaw":1,
                   "isCompleted":false,"listRaw":"haveTo","position":1000,"createdAt":"2026-10-01T09:00:00Z","actualSeconds":0,
                   "waitingOn":"","tagsRaw":""}]}
        """
        let file = try BackupFile.decode(Data(old.utf8))
        XCTAssertNil(file.vision, "backups from before Vision have no Vision section")
        XCTAssertNil(file.tasks.first?.goalID)
        XCTAssertEqual(file.tasks.first?.title, "Pay rent")
    }

    func testSanitizeDropsUnsafeAndDanglingRecords() {
        let (clean, goal, image) = visionBackup()
        var v = clean
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let ghost = UUID()
        v.images.append(.init(id: UUID(), goalID: goal, fileName: "../../Top3.store", thumbnailFileName: "", pixelWidth: 1, pixelHeight: 1,
                              caption: "", sortOrder: 2000, createdAt: at))
        v.images.append(.init(id: UUID(), goalID: goal, fileName: "b.jpg", thumbnailFileName: "/etc/hosts", pixelWidth: 1, pixelHeight: 1,
                              caption: "", sortOrder: 3000, createdAt: at))
        v.logs.append(.init(id: UUID(), goalID: ghost, date: at, text: "orphan", progress: nil, metricValue: nil, createdAt: at))
        let other = v.goals[1].id
        v.dependencies.append(.init(id: UUID(), upstreamID: goal, downstreamID: other, createdAt: at)) // closes a loop
        v.dependencies.append(.init(id: UUID(), upstreamID: other, downstreamID: goal, createdAt: at)) // duplicate
        v.dependencies.append(.init(id: UUID(), upstreamID: ghost, downstreamID: goal, createdAt: at)) // missing goal
        v.goals[1].coverImageID = image // someone else's image

        let s = v.sanitized()
        XCTAssertEqual(s.images.map(\.id), [image], "only plain file names survive")
        XCTAssertEqual(s.logs.count, 1)
        XCTAssertEqual(s.dependencies.count, 1)
        XCTAssertEqual(s.dependencies.first?.upstreamID, other)
        XCTAssertEqual(s.goals[0].coverImageID, image)
        XCTAssertNil(s.goals[1].coverImageID)
    }
}
