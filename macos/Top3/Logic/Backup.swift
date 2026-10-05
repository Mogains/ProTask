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
