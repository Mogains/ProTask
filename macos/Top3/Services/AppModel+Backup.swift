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
                               actualSeconds: t.actualSeconds, waitingOn: t.waitingOn, followUpDate: t.followUpDate, tagsRaw: t.tagsRaw)
        }
        let logs = ((try? context.fetch(FetchDescriptor<DayLog>())) ?? []).map {
            BackupFile.DayLogDTO(day: $0.day, top3Complete: $0.top3Complete, promptDismissed: $0.promptDismissed,
                                 planningDone: $0.planningDone, dayClosed: $0.dayClosed, rolledOverRaw: $0.rolledOverRaw)
        }
        let settings = ((try? context.fetch(FetchDescriptor<ListSetting>())) ?? []).map { BackupFile.ListSettingDTO(listRaw: $0.listRaw, autoSort: $0.autoSort) }
        let sessions = ((try? context.fetch(FetchDescriptor<FocusSession>())) ?? []).map {
            BackupFile.FocusDTO(id: $0.id, taskID: $0.taskID, taskTitle: $0.taskTitle, start: $0.start, seconds: $0.seconds)
        }
        return BackupFile(exportedAt: Date(), tasks: tasks, dayLogs: logs, listSettings: settings, focusSessions: sessions)
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
            context.insert(t)
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
        save()
        reloadListSettings()
        for t in allTasks() {
            if t.isIdea, let at = t.remindAt, at > Date() { notifications.schedule(id: t.id, title: t.title, at: at) }
            scheduleFollowUp(t)
        }
        runMorningReset()
        syncAllEvents()
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
            try makeBackup().encoded().write(to: backupDirectory.appending(path: name), options: .atomic)
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
