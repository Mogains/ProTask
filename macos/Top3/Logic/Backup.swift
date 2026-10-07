import Foundation

/// The JSON backup format. Plain Codable mirrors of the stored models, so it is readable and future-proof.
struct BackupFile: Codable, Equatable {
    static let formatName = "protask-backup"
    static let currentVersion = 1

    var format = BackupFile.formatName
    var version = BackupFile.currentVersion
    var exportedAt: Date
    var tasks: [TaskDTO]
    var dayLogs: [DayLogDTO]
    var listSettings: [ListSettingDTO]
    var focusSessions: [FocusDTO]
    /// Vision timelines, goals, logs, image references and dependencies (newer backups). Image bytes are never included,
    /// only the file names in the VisionImages folder. Nil in backups made before Vision.
    var vision: VisionDTO? = nil

    struct TaskDTO: Codable, Equatable {
        var id: UUID
        var title: String
        var notes: String
        var dueDate: Date?
        var hasDueTime: Bool
        var priorityRaw: Int
        var estimateMinutes: Int?
        var isCompleted: Bool
        var completedAt: Date?
        var listRaw: String
        var position: Double
        var topSlot: Int?
        var topDay: String?
        var calendarEventID: String?
        var createdAt: Date
        var remindAt: Date?
        var recurrenceRaw: String?
        var seriesID: UUID?
        var nextOccurrenceID: UUID?
        var actualSeconds: Int
        var waitingOn: String
        var followUpDate: Date?
        var tagsRaw: String
        /// Calendar event links (newer backups). Older backups only have calendarEventID.
        var links: [LinkDTO]? = nil
        /// Event deleted in Calendar (newer backups).
        var unscheduled: Bool? = nil
        /// The Vision goal the task is linked to (newer backups).
        var goalID: UUID? = nil
    }

    struct LinkDTO: Codable, Equatable {
        var kindRaw: String
        var eventIdentifier: String
        var externalIdentifier: String?
        var contentHash: String?
        var remoteModifiedAt: Date?
        var lastSyncedAt: Date
    }

    struct DayLogDTO: Codable, Equatable {
        var day: String
        var top3Complete: Bool
        var promptDismissed: Bool
        var planningDone: Bool
        var dayClosed: Bool
        var rolledOverRaw: String
    }

    struct ListSettingDTO: Codable, Equatable {
        var listRaw: String
        var autoSort: Bool
    }

    struct FocusDTO: Codable, Equatable {
        var id: UUID
        var taskID: UUID?
        var taskTitle: String
        var start: Date
        var seconds: Int
    }

    struct VisionDTO: Codable, Equatable {
        var timelines: [TimelineDTO]
        var goals: [GoalDTO]
        var logs: [GoalLogDTO]
        var images: [GoalImageDTO]
        var dependencies: [GoalDependencyDTO]
    }

    struct TimelineDTO: Codable, Equatable {
        var id: UUID
        var name: String
        var details: String
        var colorRaw: String
        var sortOrder: Double
        var archived: Bool
        var createdAt: Date
        var modifiedAt: Date
    }

    struct GoalDTO: Codable, Equatable {
        var id: UUID
        var timelineID: UUID
        var title: String
        var notes: String
        var typeRaw: String
        var statusRaw: String
        var startDate: Date?
        var targetDate: Date?
        var progress: Int
        var progressModeRaw: String
        var metricName: String
        var metricStart: Double?
        var metricCurrent: Double?
        var metricTarget: Double?
        var metricUnit: String
        var coverImageID: UUID?
        var sortOrder: Double
        var createdAt: Date
        var modifiedAt: Date
        var syncTargetToCalendar: Bool
    }

    struct GoalLogDTO: Codable, Equatable {
        var id: UUID
        var goalID: UUID
        var date: Date
        var text: String
        var progress: Int?
        var metricValue: Double?
        var createdAt: Date
    }

    /// A reference to an image file: its name only, never its bytes or a path.
    struct GoalImageDTO: Codable, Equatable {
        var id: UUID
        var goalID: UUID
        var fileName: String
        var thumbnailFileName: String
        var pixelWidth: Int
        var pixelHeight: Int
        var caption: String
        var sortOrder: Double
        var createdAt: Date
    }

    struct GoalDependencyDTO: Codable, Equatable {
        var id: UUID
        var upstreamID: UUID
        var downstreamID: UUID
        var createdAt: Date
    }

    /// ISO 8601 with fractional seconds, so a round trip loses nothing.
    private static func formatter(fractional: Bool) -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return f
    }

    func encoded() throws -> Data {
        let e = JSONEncoder()
        let f = Self.formatter(fractional: true)
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(f.string(from: date))
        }
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let d = JSONDecoder()
        let precise = formatter(fractional: true), plain = formatter(fractional: false)
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = precise.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date: \(s)")
        }
        let file = try d.decode(BackupFile.self, from: data)
        guard file.format == formatName else { throw BackupError.notABackup }
        guard file.version <= currentVersion else { throw BackupError.newerVersion }
        return file
    }

    enum BackupError: LocalizedError {
        case notABackup, newerVersion
        var errorDescription: String? {
            switch self {
            case .notABackup: "That file isn't a ProTask backup."
            case .newerVersion: "That backup was made by a newer version of ProTask."
            }
        }
    }
}

extension BackupFile.VisionDTO {
    /// What a restore keeps: image references with plain file names only (never paths), logs, images and dependencies
    /// whose goals are in the backup, covers that point at the goal's own images, and no duplicate or looping dependencies.
    func sanitized() -> Self {
        let goalIDs = Set(goals.map(\.id))
        var out = self
        out.logs = logs.filter { goalIDs.contains($0.goalID) }
        out.images = images.filter {
            goalIDs.contains($0.goalID) && VisionImageFiles.isSafeName($0.fileName)
                && ($0.thumbnailFileName.isEmpty || VisionImageFiles.isSafeName($0.thumbnailFileName))
        }
        let imageOwner = Dictionary(out.images.map { ($0.id, $0.goalID) }, uniquingKeysWith: { a, _ in a })
        out.goals = goals.map { g in
            var g = g
            if let cover = g.coverImageID, imageOwner[cover] != g.id { g.coverImageID = nil }
            return g
        }
        var edges: [GoalEdge] = []
        out.dependencies = dependencies.filter { d in
            let edge = GoalEdge(upstream: d.upstreamID, downstream: d.downstreamID)
            guard goalIDs.contains(d.upstreamID), goalIDs.contains(d.downstreamID), !edges.contains(edge),
                  !GoalGraph.wouldCreateCycle(adding: edge, to: edges) else { return false }
            edges.append(edge)
            return true
        }
        return out
    }
}

/// Human-readable Markdown export of the task lists.
enum MarkdownExport {
    static func render(_ tasks: [BackupFile.TaskDTO], now: Date = Date(), calendar: Calendar = .current) -> String {
        func meta(_ t: BackupFile.TaskDTO) -> String {
            var parts: [String] = []
            if let due = t.dueDate {
                parts.append("due " + due.formatted(t.hasDueTime ? .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
                                                                  : .dateTime.weekday(.abbreviated).month(.abbreviated).day()))
            }
            if let p = Priority(rawValue: t.priorityRaw), p != .medium { parts.append(p.title.lowercased() + " priority") }
            if let m = t.estimateMinutes { parts.append("\(m) min") }
            if let r = RecurrenceRule(encoded: t.recurrenceRaw) { parts.append("repeats " + r.summary.lowercased()) }
            if !t.waitingOn.isEmpty { parts.append("waiting on " + t.waitingOn) }
            if let f = t.followUpDate { parts.append("follow up " + f.formatted(.dateTime.month(.abbreviated).day())) }
            parts += t.tagsRaw.split(separator: " ").map { "#\($0)" }
            return parts.isEmpty ? "" : " — " + parts.joined(separator: " · ")
        }
        func line(_ t: BackupFile.TaskDTO, idea: Bool = false) -> String {
            (idea ? "- " : (t.isCompleted ? "- [x] " : "- [ ] ")) + t.title + meta(t)
        }

        var out = ["# ProTask", "", "Exported \(now.formatted(date: .long, time: .shortened))", ""]
        func section(_ title: String, _ items: [BackupFile.TaskDTO], idea: Bool = false) {
            guard !items.isEmpty else { return }
            out.append("## \(title)")
            out.append("")
            out += items.map { line($0, idea: idea) }
            out.append("")
        }
        let open = tasks.filter { !$0.isCompleted }
        section("Top 3", tasks.filter { $0.topSlot != nil }.sorted { ($0.topSlot ?? 0) < ($1.topSlot ?? 0) })
        for list in [ListKind.haveTo, .niceTo, .waitingOn] {
            section(list.title, open.filter { $0.listRaw == list.rawValue && $0.topSlot == nil }.sorted { $0.position < $1.position })
        }
        section("Parking Lot", open.filter { $0.listRaw == ListKind.parkingLot.rawValue }.sorted { $0.createdAt > $1.createdAt }, idea: true)
        let since = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        section("Done (last 30 days)", tasks.filter { $0.isCompleted && $0.topSlot == nil && ($0.completedAt ?? .distantPast) >= since }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) })
        return out.joined(separator: "\n")
    }
}

/// Daily backups are named ProTask-YYYY-MM-DD.json; only the newest `keep` are kept.
enum BackupRotation {
    static func fileName(for day: String) -> String { "ProTask-\(day).json" }

    static func toDelete(_ fileNames: [String], keep: Int = 7) -> [String] {
        let daily = fileNames.filter { $0.range(of: #"^ProTask-\d{4}-\d{2}-\d{2}\.json$"#, options: .regularExpression) != nil }
        return Array(daily.sorted(by: >).dropFirst(keep))
    }
}
