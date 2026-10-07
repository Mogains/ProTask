import AppKit
import SwiftData
import UniformTypeIdentifiers

/// JSON and Markdown export, JSON import, and the automatic daily backup (newest 7 kept).
extension AppModel {
    static let backupPathKey = "backupPath"

    var backupDirectory: URL {
        if let p = UserDefaults.standard.string(forKey: Self.backupPathKey), !p.isEmpty { return URL(fileURLWithPath: p) }
        return URL.applicationSupportDirectory.appending(path: "ProTask/Backups", directoryHint: .isDirectory)
    }

    // MARK: Snapshot

    func makeBackup() -> BackupFile {
        let tasks = allTasks().map { t in
            BackupFile.TaskDTO(id: t.id, title: t.title, notes: t.notes, dueDate: t.dueDate, hasDueTime: t.hasDueTime,
                               priorityRaw: t.priorityRaw, estimateMinutes: t.estimateMinutes, isCompleted: t.isCompleted,
                               completedAt: t.completedAt, listRaw: t.listRaw, position: t.position, topSlot: t.topSlot, topDay: t.topDay,
                               calendarEventID: t.calendarEventID, createdAt: t.createdAt, remindAt: t.remindAt,
                               recurrenceRaw: t.recurrenceRaw, seriesID: t.seriesID, nextOccurrenceID: t.nextOccurrenceID,
                               actualSeconds: t.actualSeconds, waitingOn: t.waitingOn, followUpDate: t.followUpDate, tagsRaw: t.tagsRaw,
                               links: (t.links ?? []).sorted { $0.kindRaw < $1.kindRaw }.map {
                                   BackupFile.LinkDTO(kindRaw: $0.kindRaw, eventIdentifier: $0.eventIdentifier, externalIdentifier: $0.externalIdentifier,
                                                      contentHash: $0.contentHash, remoteModifiedAt: $0.remoteModifiedAt, lastSyncedAt: $0.lastSyncedAt)
                               }, unscheduled: t.unscheduled ? true : nil, goalID: t.goalID)
        }
        let logs = ((try? context.fetch(FetchDescriptor<DayLog>())) ?? []).map {
            BackupFile.DayLogDTO(day: $0.day, top3Complete: $0.top3Complete, promptDismissed: $0.promptDismissed,
                                 planningDone: $0.planningDone, dayClosed: $0.dayClosed, rolledOverRaw: $0.rolledOverRaw)
        }
        let settings = ((try? context.fetch(FetchDescriptor<ListSetting>())) ?? []).map { BackupFile.ListSettingDTO(listRaw: $0.listRaw, autoSort: $0.autoSort) }
        let sessions = ((try? context.fetch(FetchDescriptor<FocusSession>())) ?? []).map {
            BackupFile.FocusDTO(id: $0.id, taskID: $0.taskID, taskTitle: $0.taskTitle, start: $0.start, seconds: $0.seconds)
        }
        return BackupFile(exportedAt: Date(), tasks: tasks, dayLogs: logs, listSettings: settings, focusSessions: sessions,
                          vision: makeVisionBackup())
    }

    /// Vision records for the backup. Images are referenced by file name only; their bytes are not included.
    func makeVisionBackup() -> BackupFile.VisionDTO {
        func all<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        return BackupFile.VisionDTO(
            timelines: all(VisionTimeline.self).sorted { $0.sortOrder < $1.sortOrder }.map {
                .init(id: $0.id, name: $0.name, details: $0.details, colorRaw: $0.colorRaw, sortOrder: $0.sortOrder,
                      archived: $0.archived, createdAt: $0.createdAt, modifiedAt: $0.modifiedAt)
            },
            goals: all(Goal.self).sorted { $0.sortOrder < $1.sortOrder }.map {
                .init(id: $0.id, timelineID: $0.timelineID, title: $0.title, notes: $0.notes, typeRaw: $0.typeRaw,
                      statusRaw: $0.statusRaw, startDate: $0.startDate, targetDate: $0.targetDate, progress: $0.progress,
                      progressModeRaw: $0.progressModeRaw, metricName: $0.metricName, metricStart: $0.metricStart,
                      metricCurrent: $0.metricCurrent, metricTarget: $0.metricTarget, metricUnit: $0.metricUnit,
                      coverImageID: $0.coverImageID, sortOrder: $0.sortOrder, createdAt: $0.createdAt, modifiedAt: $0.modifiedAt,
                      syncTargetToCalendar: $0.syncTargetToCalendar)
            },
            logs: all(GoalLog.self).sorted { $0.date < $1.date }.map {
                .init(id: $0.id, goalID: $0.goalID, date: $0.date, text: $0.text, progress: $0.progress,
                      metricValue: $0.metricValue, createdAt: $0.createdAt)
            },
            images: all(GoalImage.self).sorted { $0.sortOrder < $1.sortOrder }.map {
                .init(id: $0.id, goalID: $0.goalID, fileName: $0.fileName, thumbnailFileName: $0.thumbnailFileName,
                      pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight, caption: $0.caption, sortOrder: $0.sortOrder,
                      createdAt: $0.createdAt)
            },
            dependencies: all(GoalDependency.self).sorted { $0.createdAt < $1.createdAt }.map {
                .init(id: $0.id, upstreamID: $0.upstreamID, downstreamID: $0.downstreamID, createdAt: $0.createdAt)
            })
    }

    // MARK: Export

    func exportJSON() {
        save(panelTitle: "Export as JSON", name: "ProTask Backup \(today).json", type: .json) { [self] url in
            try makeBackup().encoded().write(to: url, options: .atomic)
        }
    }

    func exportMarkdown() {
        let md = UTType(filenameExtension: "md") ?? .plainText
        save(panelTitle: "Export as Markdown", name: "ProTask \(today).md", type: md) { [self] url in
            try MarkdownExport.render(makeBackup().tasks).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func save(panelTitle: String, name: String, type: UTType, write: @escaping (URL) throws -> Void) {
        let panel = NSSavePanel()
        panel.title = panelTitle
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try write(url)
            showToast("Exported to \(url.lastPathComponent).")
        } catch {
            showToast("Export failed: \(error.localizedDescription)")
        }
    }

    // MARK: Import

    func importJSON() {
        let panel = NSOpenPanel()
        panel.title = "Import ProTask Backup"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let file: BackupFile
        do { file = try BackupFile.decode(Data(contentsOf: url)) } catch {
            return showToast(error.localizedDescription)
        }

        let alert = NSAlert()
        alert.messageText = "Replace everything with this backup?"
        alert.informativeText = "\(file.tasks.count) tasks from \(file.exportedAt.formatted(date: .abbreviated, time: .shortened)). Your current data is saved to the Backups folder first."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        writeBackup(named: "ProTask-before-import-\(Int(Date().timeIntervalSince1970)).json")
        restore(file)
        showToast("Imported \(file.tasks.count) tasks.")
    }

    func restore(_ file: BackupFile) {
        for t in allTasks() { notifications.cancel(id: t.id); notifications.cancel(identifier: Self.followUpID(t.id)) }
        try? context.delete(model: TaskItem.self)
        try? context.delete(model: DayLog.self)
        try? context.delete(model: ListSetting.self)
        try? context.delete(model: FocusSession.self)
        for d in file.tasks {
            let t = TaskItem(title: d.title, list: ListKind(rawValue: d.listRaw) ?? .haveTo, position: d.position)
            t.id = d.id; t.notes = d.notes; t.dueDate = d.dueDate; t.hasDueTime = d.hasDueTime; t.priorityRaw = d.priorityRaw
            t.estimateMinutes = d.estimateMinutes; t.isCompleted = d.isCompleted; t.completedAt = d.completedAt
            t.topSlot = d.topSlot; t.topDay = d.topDay; t.calendarEventID = d.calendarEventID; t.createdAt = d.createdAt
            t.remindAt = d.remindAt; t.recurrenceRaw = d.recurrenceRaw; t.seriesID = d.seriesID; t.nextOccurrenceID = d.nextOccurrenceID
            t.actualSeconds = d.actualSeconds; t.waitingOn = d.waitingOn; t.followUpDate = d.followUpDate; t.tagsRaw = d.tagsRaw
            t.unscheduled = d.unscheduled ?? false
            t.goalID = d.goalID
            context.insert(t)
            for l in d.links ?? [] {
                let link = EventLink(kind: LinkKind(rawValue: l.kindRaw) ?? .due, eventIdentifier: l.eventIdentifier)
                link.externalIdentifier = l.externalIdentifier; link.contentHash = l.contentHash
                link.remoteModifiedAt = l.remoteModifiedAt; link.lastSyncedAt = l.lastSyncedAt
                context.insert(link)
                link.task = t
            }
        }
        for d in file.dayLogs {
            let log = DayLog(day: d.day)
            log.top3Complete = d.top3Complete; log.promptDismissed = d.promptDismissed; log.planningDone = d.planningDone
            log.dayClosed = d.dayClosed; log.rolledOverRaw = d.rolledOverRaw
            context.insert(log)
        }
        for d in file.listSettings {
            if let l = ListKind(rawValue: d.listRaw) { context.insert(ListSetting(list: l, autoSort: d.autoSort)) }
        }
        for d in file.focusSessions {
            let s = FocusSession(taskID: d.taskID, taskTitle: d.taskTitle, start: d.start, seconds: d.seconds)
            s.id = d.id
            context.insert(s)
        }
        if let vision = file.vision { restoreVision(vision) }
        // A task never keeps a link to a goal that isn't in the restored data (for example from a hand-edited file).
        let goalIDs = Set(file.vision.map { $0.goals.map(\.id) } ?? allGoals().map(\.id))
        for t in allTasks() where t.goalID.map({ !goalIDs.contains($0) }) ?? false { t.goalID = nil }
        save()
        migrateLegacyEventLinks() // older backups carry a single calendarEventID
        reloadListSettings()
        for t in allTasks() {
            if t.isIdea, let at = t.remindAt, at > Date() { notifications.schedule(id: t.id, title: t.title, at: at) }
            scheduleFollowUp(t)
        }
        runMorningReset()
        syncAllEvents()
    }

    /// Replaces the Vision records with the backup's. Backups made before Vision (no `vision` section) leave Vision as it is.
    /// Image files are never deleted here: the backup refers to them by name, and the pre-import backup may still need them.
    private func restoreVision(_ dto: BackupFile.VisionDTO) {
        let v = dto.sanitized()
        try? context.delete(model: VisionTimeline.self)
        try? context.delete(model: Goal.self)
        try? context.delete(model: GoalLog.self)
        try? context.delete(model: GoalImage.self)
        try? context.delete(model: GoalDependency.self)
        for d in v.timelines {
            let t = VisionTimeline(name: d.name, details: d.details, color: TimelineColor(named: d.colorRaw), sortOrder: d.sortOrder)
            t.id = d.id; t.colorRaw = d.colorRaw; t.archived = d.archived; t.createdAt = d.createdAt; t.modifiedAt = d.modifiedAt
            context.insert(t)
        }
        for d in v.goals {
            let g = Goal(title: d.title, timelineID: d.timelineID, sortOrder: d.sortOrder)
            g.id = d.id; g.notes = d.notes; g.typeRaw = d.typeRaw; g.statusRaw = d.statusRaw
            g.startDate = d.startDate; g.targetDate = d.targetDate; g.progress = GoalProgress.clamp(d.progress)
            g.progressModeRaw = d.progressModeRaw; g.metricName = d.metricName; g.metricStart = d.metricStart
            g.metricCurrent = d.metricCurrent; g.metricTarget = d.metricTarget; g.metricUnit = d.metricUnit
            g.coverImageID = d.coverImageID; g.createdAt = d.createdAt; g.modifiedAt = d.modifiedAt
            g.syncTargetToCalendar = d.syncTargetToCalendar
            context.insert(g)
        }
        for d in v.logs {
            let l = GoalLog(goalID: d.goalID, date: d.date, text: d.text)
            l.id = d.id; l.progress = d.progress; l.metricValue = d.metricValue; l.createdAt = d.createdAt
            context.insert(l)
        }
        for d in v.images {
            let i = GoalImage(id: d.id, goalID: d.goalID, fileName: d.fileName, thumbnailFileName: d.thumbnailFileName,
                              pixelWidth: d.pixelWidth, pixelHeight: d.pixelHeight, sortOrder: d.sortOrder)
            i.caption = d.caption; i.createdAt = d.createdAt
            context.insert(i)
        }
        for d in v.dependencies {
            let dep = GoalDependency(upstreamID: d.upstreamID, downstreamID: d.downstreamID)
            dep.id = d.id; dep.createdAt = d.createdAt
            context.insert(dep)
        }
    }

    // MARK: Automatic backup

    /// Once a day: write ProTask-YYYY-MM-DD.json and keep the newest seven.
    func autoBackupIfNeeded() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TOP3_STORE_PATH"] != nil { return }
        #endif
        let name = BackupRotation.fileName(for: today)
        guard !FileManager.default.fileExists(atPath: backupDirectory.appending(path: name).path) else { return }
        writeBackup(named: name)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: backupDirectory.path)) ?? []
        for old in BackupRotation.toDelete(names) { try? FileManager.default.removeItem(at: backupDirectory.appending(path: old)) }
    }

    func backUpNow() {
        writeBackup(named: BackupRotation.fileName(for: today))
        showToast("Backed up to \(backupDirectory.lastPathComponent).")
    }

    @discardableResult
    func writeBackup(named name: String) -> Bool {
        do {
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let url = backupDirectory.appending(path: name)
            try makeBackup().encoded().write(to: url, options: .atomic)
            FilePermissions.lockFile(url)
            return true
        } catch {
            showToast("Backup failed: \(error.localizedDescription)")
            return false
        }
    }

    func chooseBackupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: Self.backupPathKey)
        backUpNow()
    }
}
