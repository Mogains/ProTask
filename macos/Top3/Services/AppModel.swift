import AppKit
import Observation
import SwiftData
import SwiftUI

enum SidebarSection: Hashable {
    case today
    case list(ListKind)
    case calendar
    case done
    case review
}

struct EditorRequest: Identifiable {
    let id = UUID()
    var task: TaskItem?
    var list: ListKind
}

struct TaskDraft {
    var title: String
    var notes: String = ""
    var list: ListKind = .haveTo
    var priority: Priority = .medium
    var dueDate: Date?
    var hasDueTime = false
    var estimateMinutes: Int?
    var recurrence: RecurrenceRule?
    var waitingOn: String = ""
    var followUpDate: Date?
    var tags: [String] = []
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

/// Owns the data and every change to it, so calendar events, reminders and the streak stay consistent.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    @ObservationIgnored let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let calendar = CalendarService()
    @ObservationIgnored let notifications = NotificationService()

    var section: SidebarSection = .today
    var selectedTaskID: UUID?
    var editor: EditorRequest?
    var showQuickPark = false
    var showPalette = false
    /// Sidebar tag filter applied to the current view.
    var tagFilter: String?
    var tagEditRequest: TagEditRequest?
    var showPlanning = false
    var showWrapUp = false
    /// The running focus timer, if any. Persisted so it survives a restart.
    var focus: RunningFocus? = RunningFocus.load()
    /// Task id (or nil for an untitled session) awaiting a custom focus length.
    var customFocusRequest: CustomFocusRequest?
    @ObservationIgnored var focusEndTimer: Timer?
    var toast: ToastMessage?
    var celebrating = false
    private(set) var today: String
    /// Bumped on every save so views outside SwiftData queries (menu bar label, widget) refresh.
    private(set) var revision = 0
    private(set) var autoSort: [ListKind: Bool] = [:]

    var resetHour: Int { Self.savedResetHour() }

    nonisolated static func savedResetHour() -> Int {
        let v = UserDefaults.standard.object(forKey: "resetHour") as? Int
        return v.map { min(max($0, 0), 23) } ?? DayKey.defaultResetHour
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activeObserver: NSObjectProtocol?

    init() {
        let fm = FileManager.default
        let dir = URL.applicationSupportDirectory.appending(path: "ProTask", directoryHint: .isDirectory)
        // Carry data over from the app's previous name.
        let legacy = URL.applicationSupportDirectory.appending(path: "Top 3", directoryHint: .isDirectory)
        if !fm.fileExists(atPath: dir.path), fm.fileExists(atPath: legacy.path) {
            try? fm.moveItem(at: legacy, to: dir)
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // TOP3_STORE_PATH lets tests and screenshots use a throwaway database.
        let storeURL = ProcessInfo.processInfo.environment["TOP3_STORE_PATH"].map { URL(fileURLWithPath: $0) }
            ?? dir.appending(path: "Top3.store")
        let config = ModelConfiguration(url: storeURL)
        do {
            container = try ModelContainer(for: TaskItem.self, ListSetting.self, DayLog.self, FocusSession.self, configurations: config)
        } catch {
            fatalError("Could not open the ProTask database: \(error)")
        }
        today = DayKey.key(resetHour: Self.savedResetHour())
        for s in (try? context.fetch(FetchDescriptor<ListSetting>())) ?? [] {
            if let l = ListKind(rawValue: s.listRaw) { autoSort[l] = s.autoSort }
        }
        notifications.extraCategories = [Self.followUpCategory]
        notifications.onAction = { [weak self] id, action in self?.handleIdeaAction(id: id, action: action) }
        notifications.onOther = { [weak self] identifier, action in self?.handleNotification(identifier, action: action) }
    }

    // MARK: Launch and day rollover

    func onLaunch() async {
        runMorningReset()
        HotKeyService.shared.onPress = { QuickCaptureController.shared.toggle() }
        HotKeyService.shared.register(HotKey.saved)
        applyAppearance()
        resumeFocus()
        #if DEBUG
        let snapshotting = ProcessInfo.processInfo.environment["TOP3_SNAPSHOT_DIR"] != nil
        #else
        let snapshotting = false
        #endif
        if !snapshotting { checkPlanning() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkDay()
                self?.calendar.loadToday()
                self?.finishFocusIfDue()
            }
        }
        activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.checkDay()
                self?.calendar.loadToday()
            }
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["TOP3_DEMO"] != nil { seedDemoData() }
        if let dir = ProcessInfo.processInfo.environment["TOP3_SNAPSHOT_DIR"] { Task { await snapshotSections(to: dir) } }
        if ProcessInfo.processInfo.environment["TOP3_SKIP_PERMISSIONS"] != nil { return }
        #endif
        await notifications.requestAuthorization()
        scheduleEveningWrapUp()
        await calendar.requestAccess()
        syncAllEvents()
        await reconcileReminders()
    }

    func checkDay() {
        let key = DayKey.key(resetHour: resetHour)
        if key != today {
            today = key
            runMorningReset()
            syncAllEvents()
            checkPlanning()
        }
    }

    /// Unfinished picks from an earlier day go back to their list (they never left it); finished ones go to Done.
    /// Unfinished ones are remembered so morning planning can offer them again.
    func runMorningReset() {
        let all = allTasks()
        let pins = all.filter { $0.topSlot != nil }.map { Rollover.Pin(id: $0.id, topDay: $0.topDay, isCompleted: $0.isCompleted) }
        let result = Rollover.plan(pins: pins, today: today)
        guard !result.unpin.isEmpty else { return }
        for t in all where result.unpin.contains(t.id) {
            t.topSlot = nil
            t.topDay = nil
            calendar.sync(t, today: today)
        }
        addRolledOver(result.rolledOver, to: today)
        save()
    }

    func addRolledOver(_ ids: [UUID], to day: String) {
        guard !ids.isEmpty else { return }
        let log = dayLog(day)
        var existing = Rollover.decode(log.rolledOverRaw)
        for id in ids where !existing.contains(id) { existing.append(id) }
        log.rolledOverRaw = Rollover.encode(existing)
    }

    /// Morning planning shows once per day (after the reset hour) unless turned off or already done.
    func checkPlanning() {
        guard UserDefaults.standard.object(forKey: "morningPlanning") as? Bool ?? true else { return }
        if !dayLog(today).planningDone { showPlanning = true }
    }

    func finishPlanning() {
        dayLog(today).planningDone = true
        dayLog(today).promptDismissed = true
        save()
        withAnimation(Theme.Motion.list) { showPlanning = false }
        section = .today
    }

    // MARK: Queries

    func allTasks() -> [TaskItem] {
        (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
    }

    func task(_ id: UUID?) -> TaskItem? {
        guard let id else { return nil }
        return try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first
    }

    func isAutoSort(_ list: ListKind) -> Bool { autoSort[list] ?? true }

    /// Open tasks of a list in display order (auto sorted or manual).
    func ordered(_ list: ListKind, in tasks: [TaskItem]) -> [TaskItem] {
        let open = tasks.filter { $0.list == list && !$0.isCompleted && $0.topSlot == nil }
        if list == .parkingLot { return open.sorted { $0.createdAt > $1.createdAt } }
        if list == .waitingOn {
            return open.sorted { ($0.followUpDate ?? .distantFuture, $0.createdAt) < ($1.followUpDate ?? .distantFuture, $1.createdAt) }
        }
        return isAutoSort(list) ? TaskSorting.sorted(open) : open.sorted { $0.position < $1.position }
    }

    func pinned(in tasks: [TaskItem]) -> [Int: TaskItem] {
        var out: [Int: TaskItem] = [:]
        for t in tasks { if let s = t.topSlot { out[s] = t } }
        return out
    }

    func allPinnedDone(in tasks: [TaskItem]) -> Bool {
        let p = pinned(in: tasks)
        return p.count == 3 && p.values.allSatisfy(\.isCompleted)
    }

    func dayLog(_ day: String) -> DayLog {
        if let log = try? context.fetch(FetchDescriptor<DayLog>(predicate: #Predicate { $0.day == day })).first { return log }
        let log = DayLog(day: day)
        context.insert(log)
        return log
    }

    // MARK: Tasks

    func newTask(in list: ListKind? = nil) {
        var target = list ?? .haveTo
        if list == nil, case let .list(l) = section, l != .parkingLot { target = l }
        editor = EditorRequest(task: nil, list: target)
    }

    func edit(_ task: TaskItem) {
        editor = EditorRequest(task: task, list: task.list)
    }

    @discardableResult
    func addTask(_ d: TaskDraft) -> TaskItem? {
        let title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let t = TaskItem(title: title, list: d.list, position: endPosition(of: d.list))
        apply(d, to: t)
        context.insert(t)
        if t.isIdea { scheduleReminder(t) }
        scheduleFollowUp(t)
        calendar.sync(t, today: today)
        save()
        selectedTaskID = t.id
        return t
    }

    func update(_ t: TaskItem, with d: TaskDraft) {
        let oldList = t.list
        apply(d, to: t)
        if t.list != oldList {
            t.position = endPosition(of: t.list)
            if oldList == .parkingLot { notifications.cancel(id: t.id); t.remindAt = nil }
            if t.list == .parkingLot { t.topSlot = nil; t.topDay = nil; scheduleReminder(t) }
            if t.list == .waitingOn { t.topSlot = nil; t.topDay = nil }
        }
        scheduleFollowUp(t)
        calendar.sync(t, today: today)
        refreshDayLog()
        save()
    }

    private func apply(_ d: TaskDraft, to t: TaskItem) {
        t.title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        t.notes = d.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        t.list = d.list
        t.priority = d.priority
        t.dueDate = d.dueDate
        t.hasDueTime = d.dueDate != nil && d.hasDueTime
        t.estimateMinutes = d.estimateMinutes.flatMap { $0 > 0 ? min($0, 1440) : nil }
        t.recurrence = d.list == .parkingLot || d.list == .waitingOn ? nil : d.recurrence
        t.waitingOn = d.list == .waitingOn ? d.waitingOn.trimmingCharacters(in: .whitespaces) : ""
        t.followUpDate = d.list == .waitingOn ? d.followUpDate : nil
        t.tags = d.tags
        if t.recurrence != nil {
            // A repeating task needs a date to repeat from.
            if t.dueDate == nil { t.dueDate = DayKey.date(from: today) ?? Calendar.current.startOfDay(for: Date()) }
            if t.seriesID == nil { t.seriesID = t.id }
        }
    }

    func delete(_ t: TaskItem) {
        calendar.removeEvent(id: t.calendarEventID)
        notifications.cancel(id: t.id)
        notifications.cancel(identifier: Self.followUpID(t.id))
        if selectedTaskID == t.id { selectedTaskID = nil }
        let title = t.title
        context.delete(t)
        refreshDayLog()
        save()
        showToast("Deleted \"\(title)\"")
    }

    func setCompleted(_ t: TaskItem, _ done: Bool) {
        let wasAllDone = allPinnedDone(in: allTasks())
        t.isCompleted = done
        t.completedAt = done ? Date() : nil
        calendar.sync(t, today: today)
        if done { spawnNextOccurrence(of: t) }
        scheduleFollowUp(t)
        refreshDayLog()
        save()
        if !wasAllDone && allPinnedDone(in: allTasks()) { celebrate() }
    }

    /// Completing a recurring task creates its next occurrence (once). The series is never deleted.
    private func spawnNextOccurrence(of t: TaskItem) {
        guard let rule = t.recurrence, task(t.nextOccurrenceID) == nil else { return }
        let base = t.dueDate ?? Date()
        let next = TaskItem(title: t.title, list: t.list == .parkingLot ? .haveTo : t.list, position: endPosition(of: t.list))
        next.notes = t.notes
        next.priority = t.priority
        next.estimateMinutes = t.estimateMinutes
        next.hasDueTime = t.hasDueTime
        next.dueDate = rule.nextOccurrence(after: base, today: Date())
        next.recurrenceRaw = t.recurrenceRaw
        next.seriesID = t.seriesID ?? t.id
        next.tagsRaw = t.tagsRaw
        context.insert(next)
        t.nextOccurrenceID = next.id
        calendar.sync(next, today: today)
        if let due = next.dueDate {
            showToast("Next: \(due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).")
        }
    }

    private func endPosition(of list: ListKind) -> Double {
        (allTasks().filter { $0.list == list }.map(\.position).max() ?? 0) + 1000
    }

    // MARK: Ordering

    /// Moves a task into `list`, before `beforeID` (or at the end).
    /// `manual` is true for drags inside a list, which switch that list to manual order.
    func move(_ id: UUID, to list: ListKind, before beforeID: UUID?, manual: Bool) {
        guard let t = task(id), beforeID != id else { return }
        guard list != .parkingLot || t.isIdea else { return }
        let all = allTasks()
        let current = ordered(list, in: all).map(\.id)
        var ids = current.filter { $0 != id }
        let index = beforeID.flatMap { ids.firstIndex(of: $0) } ?? ids.count
        ids.insert(id, at: index)
        if t.list == list && t.topSlot == nil && ids == current { return }

        let wasIdea = t.isIdea
        let wasPinned = t.topSlot != nil
        t.list = list
        t.topSlot = nil
        t.topDay = nil
        if wasIdea && list != .parkingLot {
            notifications.cancel(id: id)
            t.remindAt = nil
        }
        if list != .waitingOn { t.followUpDate = nil }
        scheduleFollowUp(t)
        if list != .parkingLot {
            let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
            for (i, tid) in ids.enumerated() { byID[tid]?.position = Double(i + 1) * 1000 }
            if manual { setAutoSortFlag(list, false) }
        }
        if wasPinned { calendar.sync(t, today: today) }
        refreshDayLog()
        save()
    }

    func toggleAutoSort(_ list: ListKind) {
        let on = !isAutoSort(list)
        // Save the sorted order either way so nothing jumps when switching.
        for (i, t) in TaskSorting.sorted(ordered(list, in: allTasks())).enumerated() { t.position = Double(i + 1) * 1000 }
        setAutoSortFlag(list, on)
        save()
    }

    private func setAutoSortFlag(_ list: ListKind, _ on: Bool) {
        autoSort[list] = on
        let raw = list.rawValue
        if let s = try? context.fetch(FetchDescriptor<ListSetting>(predicate: #Predicate { $0.listRaw == raw })).first {
            s.autoSort = on
        } else {
            context.insert(ListSetting(list: list, autoSort: on))
        }
    }

    // MARK: Top 3

    func pin(_ id: UUID, slot: Int? = nil) {
        guard let t = task(id) else { return }
        if t.isIdea { return showToast("Send the idea to a list first.") }
        if t.isWaiting { return showToast("Move it to Have to do first.") }
        if t.isCompleted { return showToast("That one is already done.") }
        let all = allTasks()
        let occupants = all.compactMap { x in x.topSlot.map { Top3Planner.Occupant(slot: $0, taskID: x.id) } }
        switch Top3Planner.plan(occupants: occupants, taskID: id, requested: slot) {
        case .full:
            showToast(Top3Planner.fullMessage)
        case .invalidSlot:
            showToast("Pick slot 1, 2 or 3.")
        case let .assign(newSlot, displaced):
            t.topSlot = newSlot
            t.topDay = today
            if let d = displaced, let other = task(d.taskID) {
                other.topSlot = d.toSlot
                other.topDay = d.toSlot == nil ? nil : today
                calendar.sync(other, today: today)
            }
            calendar.sync(t, today: today)
            refreshDayLog()
            save()
        }
    }

    func unpin(_ t: TaskItem) {
        t.topSlot = nil
        t.topDay = nil
        calendar.sync(t, today: today)
        refreshDayLog()
        save()
    }

    func togglePin(_ t: TaskItem) {
        t.topSlot == nil ? pin(t.id) : unpin(t)
    }

    func assignSelected(to slot: Int) {
        guard let t = task(selectedTaskID) else { return showToast("Select a task first, then press Command-\(slot).") }
        pin(t.id, slot: slot)
    }

    func editSelected() {
        if let t = task(selectedTaskID) { edit(t) }
    }

    func toggleSelectedDone() {
        if let t = task(selectedTaskID), !t.isIdea { setCompleted(t, !t.isCompleted) }
    }

    func deleteSelected() {
        if let t = task(selectedTaskID) { delete(t) }
    }

    func dismissPrompt() {
        dayLog(today).promptDismissed = true
        save()
    }

    /// Records whether all three of today's picks are done. Drives the streak.
    func refreshDayLog() {
        let pins = allTasks().filter { $0.topSlot != nil && $0.topDay == today }
        let complete = pins.count == 3 && pins.allSatisfy(\.isCompleted)
        let log = dayLog(today)
        if log.top3Complete != complete { log.top3Complete = complete }
    }

    /// Hook for features that add palette actions (focus timer, review…).
    func extraPaletteActions() -> [PaletteItem] {
        [PaletteItem(id: "plan", title: "Plan my day", kind: .action, icon: .today) { [self] in showPlanning = true },
         PaletteItem(id: "wrap", title: "Wrap up the day", kind: .action, icon: .done) { [self] in showWrapUp = true },
         PaletteItem(id: "focus", title: focus == nil ? "Start focus timer" : "Stop focus timer", detail: focus == nil ? task(selectedTaskID)?.title : focus?.title,
                     shortcut: "⇧⌘F", kind: .action, icon: .later) { [self] in toggleFocusForSelection() },
         PaletteItem(id: "focus-50", title: "Start 50-minute focus", kind: .action, icon: .later) { [self] in startFocus(on: task(selectedTaskID), minutes: 50) }]
    }

    // MARK: Quick capture

    /// Saves text from a quick-add field, routed by its prefix ("~" Nice to do, "?" Parking Lot).
    @discardableResult
    func capture(_ raw: String, detectDates: Bool = true) -> Bool {
        let route = CaptureRouting.route(raw)
        guard !route.text.isEmpty else { return false }
        if route.list == .parkingLot { return addIdea(route.text) }
        let p = TaskParser.parse(route.text, detectDates: detectDates)
        let draft = TaskDraft(title: p.title, list: route.list, priority: p.priority ?? .medium, dueDate: p.dueDate,
                              hasDueTime: p.hasDueTime, estimateMinutes: p.estimateMinutes, tags: p.tags)
        guard addTask(draft) != nil else { return false }
        showToast("Added to \(route.list.title).")
        return true
    }

    // MARK: Parking Lot

    @discardableResult
    func addIdea(_ text: String) -> Bool {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        let t = TaskItem(title: title, list: .parkingLot, position: 0)
        t.createdAt = Date()
        context.insert(t)
        scheduleReminder(t)
        save()
        return true
    }

    func snooze(_ t: TaskItem) {
        scheduleReminder(t)
        save()
        showToast("Reminder moved to \(t.remindAt?.formatted(date: .omitted, time: .shortened) ?? "an hour from now").")
    }

    func send(_ t: TaskItem, to list: ListKind) {
        move(t.id, to: list, before: nil, manual: false)
        showToast("Moved to \(list.title).")
    }

    private func scheduleReminder(_ t: TaskItem) {
        let at = Date().addingTimeInterval(NotificationService.reminderInterval)
        t.remindAt = at
        notifications.schedule(id: t.id, title: t.title, at: at)
    }

    func handleIdeaAction(id: UUID, action: NotificationService.Action) {
        guard let t = task(id), t.isIdea else {
            if action == .open { NSApp.activate() }
            return
        }
        switch action {
        case .sendHaveTo: move(id, to: .haveTo, before: nil, manual: false)
        case .sendNiceTo: move(id, to: .niceTo, before: nil, manual: false)
        case .delete: delete(t)
        case .keep: scheduleReminder(t); save()
        case .open:
            NSApp.activate()
            section = .list(.parkingLot)
            selectedTaskID = id
        }
    }

    /// Re-creates reminders that should still be pending (for example after reinstalling).
    private func reconcileReminders() async {
        let pending = await notifications.pendingIDs()
        for t in allTasks() where t.isIdea {
            if let at = t.remindAt, at > Date(), !pending.contains(t.id.uuidString) {
                notifications.schedule(id: t.id, title: t.title, at: at)
            }
        }
    }

    // MARK: Calendar

    func syncAllEvents() {
        guard calendar.hasAccess else { return }
        for t in allTasks() where !t.isIdea && (t.dueDate != nil || t.topSlot != nil || t.calendarEventID != nil) {
            calendar.sync(t, today: today)
        }
        calendar.loadToday()
        save()
    }

    func requestCalendarAccess() async {
        await calendar.requestAccess()
        syncAllEvents()
    }

    // MARK: Feedback

    func showToast(_ text: String) {
        let msg = ToastMessage(text: text)
        withAnimation(Theme.Motion.standard) { toast = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + Theme.Motion.toastDuration) { [weak self] in
            guard self?.toast == msg else { return }
            withAnimation(Theme.Motion.standard) { self?.toast = nil }
        }
    }

    private func celebrate() {
        NSSound(named: "Glass")?.play()
        celebrating = true
        showToast("All three done.")
        DispatchQueue.main.asyncAfter(deadline: .now() + Theme.Motion.toastDuration) { [weak self] in
            self?.celebrating = false
        }
    }

    func save() {
        do { try context.save() } catch { showToast("Couldn't save: \(error.localizedDescription)") }
        revision += 1
        didSave()
    }

    /// Top 3 progress for the menu bar: done and pinned counts.
    var top3Progress: (done: Int, pinned: Int) {
        _ = revision
        let pins = allTasks().filter { $0.topSlot != nil }
        return (pins.filter(\.isCompleted).count, pins.count)
    }

    /// Hook for work after every save (widget snapshot).
    func didSave() {}

    #if DEBUG
    /// Renders the main window for each section to PNG files, then quits. Needs no screen-recording permission.
    private func snapshotSections(to dir: String) async {
        NSApp.activate()
        let env = ProcessInfo.processInfo.environment
        if env["TOP3_APPEARANCE"] == "light" { NSApp.appearance = NSAppearance(named: .aqua) }
        if env["TOP3_APPEARANCE"] == "dark" { NSApp.appearance = NSAppearance(named: .darkAqua) }
        try? await Task.sleep(for: .seconds(2))
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let renderer = ImageRenderer(content: IconSheet().environment(\.colorScheme, appearance == .darkAqua ? .dark : .light))
            renderer.scale = 3
            if let tiff = renderer.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: dir).appending(path: "icons-\(appearance == .darkAqua ? "dark" : "light").png"))
            }
        }
        do {
            let r = ImageRenderer(content: MenuBarQuickAdd().environment(self).modelContainer(container)
                .environment(\.colorScheme, env["TOP3_APPEARANCE"] == "light" ? .light : .dark))
            r.scale = 2
            if let tiff = r.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appending(path: "menubar.png"))
            }
        }
        let shots: [(String, SidebarSection)] = [("today", .today), ("haveto", .list(.haveTo)), ("parking", .list(.parkingLot)),
                                                  ("done", .done), ("calendar", .calendar)]
        for (name, sec) in shots {
            section = sec
            if name == "haveto" { selectedTaskID = allTasks().first { $0.title == "Gym" }?.id }
            try? await Task.sleep(for: .seconds(0.8))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
                  let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
        }
        captureWindow(as: "palette", in: dir) { self.section = .today; self.showPalette = true }
        try? await Task.sleep(for: .seconds(0.6))
        captureWindow(as: "palette", in: dir) {}
        showPalette = false
        for (name, action) in debugExtraShots() {
            action()
            try? await Task.sleep(for: .seconds(0.8))
            captureWindow(as: name, in: dir) {}
            showPlanning = false
            showWrapUp = false
            focus = nil
            tagFilter = nil
            try? await Task.sleep(for: .seconds(0.3))
        }
        if env["TOP3_SNAPSHOT_PIN4"] != nil, let extra = allTasks().first(where: { $0.title == "Read two chapters" }) {
            section = .today
            pin(extra.id)
            try? await Task.sleep(for: .seconds(0.5))
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }), let view = window.contentView?.superview,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appending(path: "full.png"))
            }
        }
        NSApp.terminate(nil)
    }

    /// Extra states to capture in debug snapshots (sheets, overlays added by later features).
    func debugExtraShots() -> [(String, () -> Void)] {
        [("planning", { self.showPlanning = true }), ("wrapup", { self.showWrapUp = true }),
         ("waiting", { self.section = .list(.waitingOn) }), ("today2", { self.section = .today }),
         ("tagfilter", { self.section = .list(.haveTo); self.tagFilter = "work" }),
         ("review", { self.section = .review }),
         ("focus", {
             self.section = .list(.haveTo)
             // In memory only, so snapshots never touch real preferences.
             self.focus = RunningFocus(taskID: nil, title: "Finish quarterly report", start: Date().addingTimeInterval(-7 * 60), seconds: 25 * 60)
         })]
    }

    private func captureWindow(as name: String, in dir: String, before: () -> Void) {
        before()
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
    }

    /// Sample data for screenshots (debug builds, TOP3_DEMO set, empty store only).
    private func seedDemoData() {
        guard allTasks().isEmpty else { return }
        let cal = Calendar.current
        let now = Date()
        func add(_ title: String, _ list: ListKind, priority: Priority = .medium, due: Date? = nil, time: Bool = false,
                 est: Int? = nil, notes: String = "") -> TaskItem {
            let t = addTask(TaskDraft(title: title, notes: notes, list: list, priority: priority, dueDate: due,
                                      hasDueTime: time, estimateMinutes: est))!
            return t
        }
        let report = add("Finish quarterly report", .haveTo, priority: .high, due: cal.date(bySettingHour: 15, minute: 0, second: 0, of: now), time: true, est: 90)
        let rent = add("Pay rent", .haveTo, due: cal.startOfDay(for: now), est: 5)
        _ = add("Reply to Sam about the offsite", .haveTo, est: 15)
        _ = add("Book dentist appointment", .haveTo, priority: .low, due: cal.date(byAdding: .day, value: 3, to: now), est: 10)
        let gym = add("Gym", .haveTo, est: 45)
        _ = add("Renew passport", .haveTo, priority: .high, due: cal.date(byAdding: .day, value: 9, to: now), est: 30, notes: "Photos are in the drawer.")
        _ = add("Read two chapters", .niceTo, priority: .low, est: 40)
        _ = add("Clean up the photo library", .niceTo, est: 60)
        _ = add("Try the new ramen place", .niceTo)
        let done = add("Water the plants", .niceTo, est: 5)
        done.isCompleted = true
        done.completedAt = now.addingTimeInterval(-3600)
        pin(report.id, slot: 1)
        pin(rent.id, slot: 2)
        pin(gym.id, slot: 3)
        rent.isCompleted = true
        rent.completedAt = now.addingTimeInterval(-1800)
        for idea in ["Weekly review template", "Ask about the standing desk budget"] { addIdea(idea) }
        for d in 1...4 { dayLog(DayKey.adding(-d, to: today)).top3Complete = true }
        if let passport = allTasks().first(where: { $0.title == "Renew passport" }) { addRolledOver([passport.id], to: today) }
        report.actualSeconds = 40 * 60
        report.tags = ["work"]
        context.insert(FocusSession(taskID: report.id, taskTitle: report.title, start: now.addingTimeInterval(-7200), seconds: 40 * 60))
        allTasks().first { $0.title == "Reply to Sam about the offsite" }?.tags = ["work", "team"]
        allTasks().first { $0.title == "Book dentist appointment" }?.tags = ["errands"]
        addTask(TaskDraft(title: "Contract redlines", list: .waitingOn, waitingOn: "Legal", followUpDate: cal.startOfDay(for: now)))
        addTask(TaskDraft(title: "Logo options", list: .waitingOn, waitingOn: "Maya",
                          followUpDate: cal.date(byAdding: .day, value: 4, to: cal.startOfDay(for: now))))
        refreshDayLog()
        selectedTaskID = nil
        save()
    }
    #endif
}
