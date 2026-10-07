import AppKit
import SwiftData

/// Vision: timelines, goals, progress logs, images and goal dependencies.
/// Private to this Mac. Nothing here is shared, uploaded or logged, and toasts never show file paths.
/// Records reference each other by UUID, so every delete removes its dependents here explicitly.
extension AppModel {
    var visionImageStore: VisionImageStore { .standard }

    // MARK: Queries

    /// Timelines in board order. Archived ones only when asked for.
    func visionTimelines(includeArchived: Bool = false) -> [VisionTimeline] {
        let all = (try? context.fetch(FetchDescriptor<VisionTimeline>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        return includeArchived ? all : all.filter { !$0.archived }
    }

    func visionTimeline(_ id: UUID?) -> VisionTimeline? {
        guard let id else { return nil }
        return try? context.fetch(FetchDescriptor<VisionTimeline>(predicate: #Predicate { $0.id == id })).first
    }

    func allGoals() -> [Goal] {
        (try? context.fetch(FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }

    func goal(_ id: UUID?) -> Goal? {
        guard let id else { return nil }
        return try? context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.id == id })).first
    }

    /// A timeline's goals in manual order.
    func goals(in timelineID: UUID) -> [Goal] {
        (try? context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.timelineID == timelineID },
                                                  sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }

    /// Newest first.
    func goalLogs(for goalID: UUID) -> [GoalLog] {
        (try? context.fetch(FetchDescriptor<GoalLog>(predicate: #Predicate { $0.goalID == goalID },
                                                     sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    func goalImages(for goalID: UUID) -> [GoalImage] {
        (try? context.fetch(FetchDescriptor<GoalImage>(predicate: #Predicate { $0.goalID == goalID },
                                                       sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }

    func goalImage(_ id: UUID?) -> GoalImage? {
        guard let id else { return nil }
        return try? context.fetch(FetchDescriptor<GoalImage>(predicate: #Predicate { $0.id == id })).first
    }

    func goalDependencies() -> [GoalDependency] {
        (try? context.fetch(FetchDescriptor<GoalDependency>())) ?? []
    }

    /// Dependencies where the goal is on either end.
    func dependencies(touching goalID: UUID) -> [GoalDependency] {
        (try? context.fetch(FetchDescriptor<GoalDependency>(predicate: #Predicate { $0.upstreamID == goalID || $0.downstreamID == goalID }))) ?? []
    }

    func linkedTasks(of goalID: UUID) -> [TaskItem] {
        let id: UUID? = goalID
        return (try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.goalID == id }))) ?? []
    }

    /// The progress the goal shows (see GoalProgress.effective).
    func effectiveProgress(of goal: Goal) -> Int {
        let tasks = goal.progressMode == .auto ? linkedTasks(of: goal.id) : []
        return GoalProgress.effective(mode: goal.progressMode, manual: goal.progress, status: goal.status, metric: goal.metric,
                                      linkedDone: tasks.filter(\.isCompleted).count, linkedTotal: tasks.count)
    }

    // MARK: Timelines

    @discardableResult
    func createTimeline(_ draft: TimelineDraft) -> VisionTimeline? {
        guard let d = draft.normalized() else { return nil }
        let all = visionTimelines(includeArchived: true)
        let timeline = VisionTimeline(name: d.name, details: d.details, color: d.color,
                                      sortOrder: VisionOrder.end(after: all.map(\.sortOrder)))
        context.insert(timeline)
        save()
        return timeline
    }

    @discardableResult
    func createTimeline(from template: TimelineTemplate) -> VisionTimeline? {
        createTimeline(TimelineDraft(template: template))
    }

    /// The color a new timeline gets: the least used one so far.
    func nextTimelineColor() -> TimelineColor {
        TimelineColor.next(after: visionTimelines(includeArchived: true).map(\.color))
    }

    func updateTimeline(_ timeline: VisionTimeline, with draft: TimelineDraft) {
        guard let d = draft.normalized() else { return }
        timeline.name = d.name
        timeline.details = d.details
        timeline.color = d.color
        timeline.modifiedAt = Date()
        save()
    }

    func setArchived(_ timeline: VisionTimeline, _ archived: Bool) {
        guard timeline.archived != archived else { return }
        timeline.archived = archived
        timeline.modifiedAt = Date()
        save()
    }

    /// Puts timelines in this order. Ones not listed keep their keys after the listed ones.
    func reorderTimelines(_ ids: [UUID]) {
        let all = visionTimelines(includeArchived: true)
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen: Set<UUID> = []
        let listed = ids.filter { byID[$0] != nil && seen.insert($0).inserted }
        let rest = all.map(\.id).filter { !listed.contains($0) }
        for (id, key) in zip(listed + rest, VisionOrder.keys(count: listed.count + rest.count)) { byID[id]?.sortOrder = key }
        save()
    }

    func moveTimeline(_ id: UUID, before beforeID: UUID?) {
        reorderTimelines(VisionOrder.moving(id, before: beforeID, in: visionTimelines(includeArchived: true).map(\.id)))
    }

    /// Deletes the timeline with all of its goals (and their logs, images, files and dependencies).
    func deleteTimeline(_ timeline: VisionTimeline) {
        var files: [String] = []
        for goal in goals(in: timeline.id) { files += removeGoalRecords(goal) }
        let name = timeline.name
        context.delete(timeline)
        save()
        visionImageStore.delete(files)
        showToast("Deleted \"\(name)\"")
    }

    // MARK: Goals

    @discardableResult
    func createGoal(_ draft: GoalDraft) -> Goal? {
        guard let d = draft.normalized(), visionTimeline(d.timelineID) != nil else { return nil }
        let goal = Goal(title: d.title, timelineID: d.timelineID,
                        sortOrder: VisionOrder.end(after: goals(in: d.timelineID).map(\.sortOrder)))
        apply(d, to: goal)
        context.insert(goal)
        save()
        return goal
    }

    func updateGoal(_ goal: Goal, with draft: GoalDraft) {
        guard let d = draft.normalized() else { return }
        if d.timelineID != goal.timelineID, visionTimeline(d.timelineID) != nil {
            goal.sortOrder = VisionOrder.end(after: goals(in: d.timelineID).map(\.sortOrder))
            goal.timelineID = d.timelineID
        }
        apply(d, to: goal)
        goal.modifiedAt = Date()
        save()
    }

    private func apply(_ d: GoalDraft, to goal: Goal) {
        goal.title = d.title
        goal.notes = d.notes
        goal.type = d.type
        goal.status = d.status
        goal.startDate = d.startDate
        goal.targetDate = d.targetDate
        goal.progress = d.progress
        goal.progressMode = d.progressMode
        goal.metric = d.metric
        goal.syncTargetToCalendar = d.syncTargetToCalendar
    }

    func setStatus(_ goal: Goal, _ status: GoalStatus) {
        guard goal.status != status else { return }
        goal.status = status
        goal.modifiedAt = Date()
        save()
    }

    func setProgress(_ goal: Goal, _ value: Int) {
        goal.progress = GoalProgress.clamp(value)
        goal.modifiedAt = Date()
        save()
    }

    /// Records the metric's new current value (only for goals that have a metric).
    func setMetricValue(_ goal: Goal, _ value: Double) {
        guard goal.metric != nil, value.isFinite else { return }
        goal.metricCurrent = value
        goal.modifiedAt = Date()
        save()
    }

    /// Puts goals in this order (within whatever timelines they are on).
    func reorderGoals(_ ids: [UUID]) {
        let byID = Dictionary(allGoals().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen: Set<UUID> = []
        let listed = ids.filter { byID[$0] != nil && seen.insert($0).inserted }
        for (id, key) in zip(listed, VisionOrder.keys(count: listed.count)) { byID[id]?.sortOrder = key }
        save()
    }

    /// Moves a goal onto `timelineID`, in front of `beforeID` (or to the end).
    func moveGoal(_ id: UUID, to timelineID: UUID, before beforeID: UUID?) {
        guard let goal = goal(id), visionTimeline(timelineID) != nil else { return }
        let ids = goals(in: timelineID).map(\.id)
        if goal.timelineID != timelineID {
            goal.timelineID = timelineID
            goal.modifiedAt = Date()
        }
        reorderGoals(VisionOrder.moving(id, before: beforeID, in: ids))
    }

    /// New dates from dragging or resizing on the timeline (already in order, whole days).
    func setGoalDates(_ goal: Goal, start: Date?, target: Date?) {
        let cal = Calendar.current
        let s = start.map { cal.startOfDay(for: $0) }, t = target.map { cal.startOfDay(for: $0) }
        guard goal.startDate != s || goal.targetDate != t else { return }
        goal.startDate = s
        goal.targetDate = t
        goal.modifiedAt = Date()
        save()
    }

    /// Moves every goal of `source` to the end of `destination`, keeping their order.
    func moveGoals(from source: VisionTimeline, to destination: VisionTimeline) {
        guard source.id != destination.id else { return }
        var key = VisionOrder.end(after: goals(in: destination.id).map(\.sortOrder))
        for goal in goals(in: source.id) {
            goal.timelineID = destination.id
            goal.sortOrder = key
            goal.modifiedAt = Date()
            key += VisionOrder.step
        }
        save()
    }

    /// Moves the goals to `destination`, then deletes the empty timeline.
    func deleteTimeline(_ timeline: VisionTimeline, movingGoalsTo destination: VisionTimeline) {
        moveGoals(from: timeline, to: destination)
        deleteTimeline(timeline)
    }

    /// A new timeline with a placeholder name and the least used color, ready to be renamed.
    @discardableResult
    func createBlankTimeline() -> VisionTimeline? {
        let used = Set(visionTimelines(includeArchived: true).map(\.name))
        var name = "New timeline"
        var n = 2
        while used.contains(name) { name = "New timeline \(n)"; n += 1 }
        return createTimeline(TimelineDraft(name: name, color: nextTimelineColor()))
    }

    /// Swaps a timeline with its neighbor among the lanes the board shows (step -1 up, 1 down).
    func moveTimelineAmongShown(_ id: UUID, by step: Int) {
        let shown = visionTimelines(includeArchived: visionBoard.showArchived).map(\.id)
        guard let i = shown.firstIndex(of: id), shown.indices.contains(i + step) else { return }
        moveTimeline(id, before: LaneReorder.beforeID(moving: i, to: i + step, ids: shown))
    }

    /// The timeline quick add uses when there is none yet.
    func ensureTimelineForQuickAdd() -> VisionTimeline? {
        if let first = visionTimelines().first { return first }
        return createTimeline(TimelineDraft(name: "Personal", color: nextTimelineColor()))
    }

    /// Selects a goal on the board, and opens its summary panel when asked.
    func selectGoal(_ id: UUID?, open: Bool = false) {
        selectedGoalID = id
        if open || visionBoard.openGoalID != nil { visionBoard.openGoalID = id }
    }

    /// Deletes the goal and clears it from the board's selection.
    func deleteGoalFromBoard(_ goal: Goal) {
        if selectedGoalID == goal.id { selectedGoalID = nil }
        if visionBoard.openGoalID == goal.id { visionBoard.openGoalID = nil }
        deleteGoal(goal)
    }

    /// Deletes the goal with its logs, images (and their files) and dependencies, and unlinks its tasks.
    func deleteGoal(_ goal: Goal) {
        let title = goal.title
        let files = removeGoalRecords(goal)
        save()
        visionImageStore.delete(files)
        showToast("Deleted \"\(title)\"")
    }

    /// Deletes a goal and everything that points at it, without saving. Returns the image files to remove once saved.
    private func removeGoalRecords(_ goal: Goal) -> [String] {
        let id = goal.id
        for log in goalLogs(for: id) { context.delete(log) }
        let images = goalImages(for: id)
        for image in images { context.delete(image) }
        for dep in dependencies(touching: id) { context.delete(dep) }
        for task in linkedTasks(of: id) { task.goalID = nil }
        context.delete(goal)
        return images.flatMap(\.fileNames)
    }

    // MARK: Log

    /// Adds a dated note, remembering the progress and metric value at that moment.
    @discardableResult
    func addGoalLog(to goal: Goal, text: String, date: Date = Date()) -> GoalLog? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        let log = GoalLog(goalID: goal.id, date: date, text: body)
        log.progress = effectiveProgress(of: goal)
        log.metricValue = goal.metric?.current
        context.insert(log)
        goal.modifiedAt = Date()
        save()
        return log
    }

    func updateGoalLog(_ log: GoalLog, text: String, date: Date) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        log.text = body
        log.date = date
        save()
    }

    func deleteGoalLog(_ log: GoalLog) {
        context.delete(log)
        save()
    }

    // MARK: Links

    /// Links a task to a goal, or unlinks it with nil.
    func linkTask(_ task: TaskItem, to goal: Goal?) {
        guard task.goalID != goal?.id else { return }
        task.goalID = goal?.id
        save()
    }

    /// `downstream` depends on `upstream`. Refuses duplicates and anything that would make a loop.
    @discardableResult
    func addDependency(upstream: Goal, downstream: Goal) -> Bool {
        let edge = GoalEdge(upstream: upstream.id, downstream: downstream.id)
        let edges = goalDependencies().map(\.edge)
        if edges.contains(edge) { return true }
        if GoalGraph.wouldCreateCycle(adding: edge, to: edges) {
            showToast("That link would make a loop.")
            return false
        }
        context.insert(GoalDependency(upstreamID: edge.upstream, downstreamID: edge.downstream))
        save()
        return true
    }

    func removeDependency(upstream: UUID, downstream: UUID) {
        for dep in goalDependencies() where dep.upstreamID == upstream && dep.downstreamID == downstream { context.delete(dep) }
        save()
    }

    // MARK: Images

    /// Processes the image off the main thread (downscale, upright, strip metadata), saves it, and adds it to the goal.
    /// The first image becomes the cover.
    @discardableResult
    func addImage(to goal: Goal, from source: VisionImageStore.Source) async -> GoalImage? {
        let store = visionImageStore
        let goalID = goal.id
        let result = await Task.detached(priority: .userInitiated) { () -> Result<VisionImageStore.Stored, VisionImageStore.ImportError> in
            do { return .success(try store.importImage(source)) } catch let e as VisionImageStore.ImportError {
                return .failure(e)
            } catch {
                return .failure(.unreadable)
            }
        }.value
        switch result {
        case let .failure(error):
            showToast(error.errorDescription ?? "Couldn't add the image.")
            return nil
        case let .success(stored):
            // The goal may have been deleted while the image was processing.
            guard let goal = self.goal(goalID) else {
                store.delete(stored.fileNames)
                return nil
            }
            return insertImage(stored, into: goal)
        }
    }

    /// Adds the image on the clipboard to the goal.
    @discardableResult
    func pasteImage(into goal: Goal) async -> GoalImage? {
        guard let source = VisionImageStore.pasteboardImage() else {
            showToast(VisionImageStore.ImportError.nothingToPaste.errorDescription ?? "")
            return nil
        }
        return await addImage(to: goal, from: source)
    }

    private func insertImage(_ stored: VisionImageStore.Stored, into goal: Goal) -> GoalImage {
        let image = GoalImage(id: stored.id, goalID: goal.id, fileName: stored.fileName, thumbnailFileName: stored.thumbnailFileName,
                              pixelWidth: stored.pixelWidth, pixelHeight: stored.pixelHeight,
                              sortOrder: VisionOrder.end(after: goalImages(for: goal.id).map(\.sortOrder)))
        context.insert(image)
        if goal.coverImageID == nil { goal.coverImageID = image.id }
        goal.modifiedAt = Date()
        save()
        return image
    }

    /// Removes the image and its files. A removed cover passes to the next image.
    func removeImage(_ image: GoalImage) {
        let files = image.fileNames
        let goalID = image.goalID
        let id = image.id
        if let goal = goal(goalID), goal.coverImageID == id {
            goal.coverImageID = goalImages(for: goalID).first { $0.id != id }?.id
            goal.modifiedAt = Date()
        }
        context.delete(image)
        save()
        visionImageStore.delete(files)
    }

    /// Sets the goal's cover (nil for none). Only the goal's own images can be its cover.
    func setCover(_ image: GoalImage?, for goal: Goal) {
        if let image, image.goalID != goal.id { return }
        goal.coverImageID = image?.id
        goal.modifiedAt = Date()
        save()
    }

    func updateImageCaption(_ image: GoalImage, _ caption: String) {
        image.caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    // MARK: Demo data

    #if DEBUG
    /// Vision sample data for screenshots. Called from seedDemoData (debug builds, TOP3_DEMO, empty store only).
    func seedVisionDemoData() {
        guard visionTimelines(includeArchived: true).isEmpty else { return }
        // TOP3_VISION_EMPTY leaves Vision empty, for screenshots of the first-run state.
        if ProcessInfo.processInfo.environment["TOP3_VISION_EMPTY"] != nil { return }
        let cal = Calendar.current
        let now = Date()
        func months(_ n: Int) -> Date { cal.date(byAdding: .month, value: n, to: cal.startOfDay(for: now)) ?? now }
        func days(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: cal.startOfDay(for: now)) ?? now }

        guard let career = createTimeline(from: TimelineTemplate.named("career")!),
              let health = createTimeline(from: TimelineTemplate.named("health")!),
              let finance = createTimeline(from: TimelineTemplate.named("finance")!),
              let projects = createTimeline(from: TimelineTemplate.named("projects")!),
              let education = createTimeline(from: TimelineTemplate.named("education")!) else { return }

        func make(_ title: String, on t: VisionTimeline, _ type: GoalType = .goal, _ status: GoalStatus = .active,
                  start: Date? = nil, target: Date? = nil, progress: Int = 0, mode: ProgressMode = .manual,
                  metric: GoalMetric? = nil, notes: String = "") -> Goal? {
            createGoal(GoalDraft(title: title, notes: notes, timelineID: t.id, type: type, status: status, startDate: start,
                                 targetDate: target, progress: progress, progressMode: mode, metric: metric))
        }

        let lead = make("Lead the platform team", on: career, start: months(-3), target: months(9), progress: 35,
                        notes: "Grow from tech lead to team lead: hiring, roadmap, and fewer late nights.")
        let billing = make("Ship the billing migration", on: career, .milestone, start: months(-1), target: days(40), mode: .auto)
        _ = make("Speak at a conference", on: career, .goal, .idea, target: months(14))
        let half = make("Run a half marathon", on: health, start: months(-2), target: months(4), mode: .auto,
                        metric: GoalMetric(name: "Long run", start: 5, current: 12, target: 21.1, unit: "km"))
        _ = make("In bed by 11 on weeknights", on: health, .habitTarget, start: days(-30), target: months(2), progress: 60)
        let car = make("Pay off the car loan", on: finance, start: months(-6), target: months(8), mode: .auto,
                       metric: GoalMetric(name: "Balance", start: 14_000, current: 8_600, target: 0, unit: "USD"))
        _ = make("Six-month emergency fund", on: finance, .goal, .planned, start: months(1), target: months(18), mode: .auto,
                 metric: GoalMetric(name: "Saved", start: 4_000, current: 4_000, target: 24_000, unit: "USD"))
        let studio = make("Finish the garden studio", on: projects, .goal, .planned, start: months(2), target: months(7), progress: 10)
        _ = make("Publish the photo book", on: projects, .goal, .idea)
        _ = make("Finish the Spanish B1 course", on: education, .goal, .done, start: months(-10), target: months(-1), progress: 100)
        setArchived(education, true)

        // More across the past and the next few years, so every zoom level has something to show.
        _ = make("Mentor two new engineers", on: career, .goal, .done, start: months(-9), target: months(-2), progress: 100)
        _ = make("Promotion review", on: career, .milestone, .planned, target: months(5))
        _ = make("Knee physio routine", on: health, .habitTarget, start: months(-3), target: days(-9), progress: 70)
        _ = make("Half marathon race day", on: health, .milestone, .planned, target: months(4))
        _ = make("Run a full marathon", on: health, .goal, .idea, start: months(18), target: months(30))
        _ = make("Open a retirement account", on: finance, .milestone, .done, target: months(-4))
        if let life = createTimeline(from: TimelineTemplate.named("life")!) {
            _ = make("Move into the new flat", on: life, .milestone, .planned, target: days(52))
            _ = make("Two weeks in Japan", on: life, .goal, .planned, start: months(11), target: cal.date(byAdding: .day, value: 13, to: months(11)))
            _ = make("Learn to bake sourdough", on: life, .goal, .active, start: days(-20), target: months(2), progress: 25)
        }

        if let billing, let lead { addDependency(upstream: billing, downstream: lead) }
        if let half {
            for (offset, text) in [(-21, "First 10k without stopping."), (-9, "Long run up to 12k. Knees fine."), (-2, "Signed up for the October race.")] {
                if let log = addGoalLog(to: half, text: text, date: days(offset)) { log.createdAt = days(offset) }
            }
            allTasks().first { $0.title == "Gym" }?.goalID = half.id
        }
        if let car { addGoalLog(to: car, text: "Extra payment from the bonus.", date: days(-12)) }
        if let lead { allTasks().first { $0.title == "Finish quarterly report" }?.goalID = lead.id }
        if let billing {
            for title in ["Migrate invoices to the new ledger", "Switch the payment webhooks"] {
                if let t = addTask(TaskDraft(title: title, list: .haveTo, priority: .medium)) { t.goalID = billing.id }
            }
            if let done = allTasks().first(where: { $0.title == "Migrate invoices to the new ledger" }) {
                done.isCompleted = true
                done.completedAt = days(-3)
            }
        }
        if let studio, let data = demoImageData(), let stored = try? visionImageStore.importImage(data: data) {
            _ = insertImage(stored, into: studio)
        }
        save()
    }

    /// A soft tonal ramp of one palette hue, larger than the 2000px limit so the downscale runs.
    private func demoImageData() -> Data? {
        let width = 2400, height = 1600
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let pair = ColorTokens.timeline(TimelineColor.sage.rawValue)
        let colors = [NSColor(hex: pair.dark).cgColor, NSColor(hex: pair.light).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return nil }
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
    #endif
}
