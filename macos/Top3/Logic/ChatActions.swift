import Foundation

/// Turns a pasted AI reply into proposed task changes. The text is untrusted: only the protask-actions
/// block is read, only four actions exist (add, move, top3, due), and anything else is dropped and listed
/// as ignored. There is no delete, no settings change and no file access, whatever the text says.
enum ChatActions {
    enum Action: Equatable {
        case add(list: ListKind, title: String, due: Date?, hasTime: Bool)
        case move(title: String, to: ListKind)
        case top3(slot: Int, title: String)
        case due(title: String, date: Date, hasTime: Bool)
    }

    struct Ignored: Equatable {
        var line: String
        var reason: String
    }

    struct Parsed: Equatable {
        var actions: [Action] = []
        var ignored: [Ignored] = []
        var foundBlock = false
    }

    static let maxActions = 20
    static let maxLineLength = 300
    static let maxTitleLength = 200
    static let blockLabel = "protask-actions"

    // MARK: Parse

    static func parse(_ text: String, calendar: Calendar = .current) -> Parsed {
        var result = Parsed()
        let blocks = extractBlocks(text)
        guard let block = blocks.last else { return result }
        result.foundBlock = true
        if blocks.count > 1 {
            result.ignored.append(Ignored(line: "\(blocks.count - 1) earlier \(blockLabel) block(s)",
                                          reason: "Only the last block is used"))
        }
        for raw in block {
            let line = sanitize(raw)
            if line.isEmpty { continue }
            if line.count > maxLineLength {
                result.ignored.append(Ignored(line: shorten(line), reason: "Line too long"))
                continue
            }
            if result.actions.count >= maxActions {
                result.ignored.append(Ignored(line: shorten(line), reason: "More than \(maxActions) actions"))
                continue
            }
            switch parseLine(line, calendar: calendar) {
            case let .success(action): result.actions.append(action)
            case let .failure(reason): result.ignored.append(Ignored(line: shorten(line), reason: reason.text))
            }
        }
        return result
    }

    /// Lines of every protask-actions block: fenced (```protask-actions … ```), or, when the reply was copied
    /// as rendered text without its fences, a bare "protask-actions" line followed by action lines.
    static func extractBlocks(_ text: String) -> [[String]] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [[String]] = []
        var i = 0
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if isFenceOpen(t) {
                var body: [String] = []
                i += 1
                while i < lines.count, !isFenceClose(lines[i].trimmingCharacters(in: .whitespaces)) {
                    body.append(lines[i])
                    i += 1
                }
                blocks.append(body)
            } else if t.lowercased() == blockLabel {
                var body: [String] = []
                i += 1
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.isEmpty && !body.isEmpty { break }
                    if !l.isEmpty && !l.contains("|") { break }
                    if !l.isEmpty { body.append(l) }
                    i += 1
                }
                blocks.append(body)
                continue
            }
            i += 1
        }
        return blocks
    }

    private static func isFenceOpen(_ t: String) -> Bool {
        guard t.hasPrefix("```") || t.hasPrefix("~~~") else { return false }
        return t.drop(while: { $0 == "`" || $0 == "~" }).trimmingCharacters(in: .whitespaces).lowercased() == blockLabel
    }

    private static func isFenceClose(_ t: String) -> Bool {
        (t.hasPrefix("```") || t.hasPrefix("~~~")) && t.allSatisfy { $0 == "`" || $0 == "~" }
    }

    struct Reason: Error, Equatable {
        let text: String
        init(_ text: String) { self.text = text }
    }

    private static func parseLine(_ line: String, calendar: Calendar) -> Result<Action, Reason> {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        let verb = f[0].lowercased()
        switch verb {
        case "add":
            guard f.count == 3 || f.count == 4 else { return .failure(Reason("Expected: add | list | title | due date")) }
            guard let list = listKind(f[1]) else { return .failure(Reason("Unknown list \"\(shorten(f[1], to: 40))\"")) }
            guard let title = title(f[2]) else { return .failure(Reason("Missing or too long title")) }
            var due: (Date, Bool)?
            if f.count == 4 {
                let field = f[3]
                guard field.lowercased().hasPrefix("due ") else { return .failure(Reason("The fourth part must be \"due YYYY-MM-DD\"")) }
                guard let d = date(String(field.dropFirst(4)), calendar: calendar) else { return .failure(Reason("Couldn't read the date")) }
                due = d
            }
            return .success(.add(list: list, title: title, due: due?.0, hasTime: due?.1 ?? false))
        case "move":
            guard f.count == 3 else { return .failure(Reason("Expected: move | task title | list")) }
            guard let title = title(f[1]) else { return .failure(Reason("Missing or too long title")) }
            guard let list = listKind(f[2]) else { return .failure(Reason("Unknown list \"\(shorten(f[2], to: 40))\"")) }
            return .success(.move(title: title, to: list))
        case "top3", "top 3":
            guard f.count == 3 else { return .failure(Reason("Expected: top3 | 1, 2 or 3 | task title")) }
            guard let slot = Int(f[1]), (1...3).contains(slot) else { return .failure(Reason("Slot must be 1, 2 or 3")) }
            guard let title = title(f[2]) else { return .failure(Reason("Missing or too long title")) }
            return .success(.top3(slot: slot, title: title))
        case "due", "set due", "set due date":
            guard f.count == 3 else { return .failure(Reason("Expected: due | task title | YYYY-MM-DD")) }
            guard let title = title(f[1]) else { return .failure(Reason("Missing or too long title")) }
            guard let d = date(f[2], calendar: calendar) else { return .failure(Reason("Couldn't read the date")) }
            return .success(.due(title: title, date: d.0, hasTime: d.1))
        default:
            return .failure(Reason("Not an allowed action (only add, move, top3, due)"))
        }
    }

    static func listKind(_ s: String) -> ListKind? {
        let t = s.lowercased().replacingOccurrences(of: " ", with: "")
        return ListKind.allCases.first { $0.title.lowercased().replacingOccurrences(of: " ", with: "") == t }
    }

    private static func title(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'` ").union(.whitespaces))
        return t.isEmpty || t.count > maxTitleLength ? nil : t
    }

    /// "YYYY-MM-DD" or "YYYY-MM-DD HH:mm" (24-hour), local time. Returns the date and whether it has a time.
    static func date(_ s: String, calendar: Calendar) -> (Date, Bool)? {
        let t = s.trimmingCharacters(in: .whitespaces)
        let parts = t.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        let ymd = parts[0].split(separator: "-")
        guard ymd.count == 3, ymd[0].count == 4, ymd[1].count == 2, ymd[2].count == 2,
              let y = Int(ymd[0]), let m = Int(ymd[1]), let d = Int(ymd[2]) else { return nil }
        var c = DateComponents(year: y, month: m, day: d)
        var hasTime = false
        if parts.count == 2 {
            let hm = parts[1].split(separator: ":")
            guard hm.count == 2, hm[1].count == 2, let h = Int(hm[0]), let mi = Int(hm[1]),
                  (0...23).contains(h), (0...59).contains(mi) else { return nil }
            c.hour = h
            c.minute = mi
            hasTime = true
        }
        guard let date = calendar.date(from: c) else { return nil }
        // Reject rollovers like 2026-02-31.
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == y, back.month == m, back.day == d else { return nil }
        return (date, hasTime)
    }

    /// Strips control and invisible formatting characters, collapses whitespace.
    static func sanitize(_ s: String) -> String {
        let scalars = s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0.properties.generalCategory != .format }
        return String(String.UnicodeScalarView(scalars)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func shorten(_ s: String, to limit: Int = 80) -> String {
        s.count > limit ? String(s.prefix(limit - 1)) + "…" : s
    }

    // MARK: Resolve against your tasks

    struct TaskRef: Equatable {
        var id: UUID
        var title: String
        var list: ListKind
        var isCompleted = false
        var topSlot: Int?
    }

    enum Change: Equatable {
        case add(list: ListKind, title: String, due: Date?, hasTime: Bool)
        case move(id: UUID, title: String, to: ListKind)
        case top3(slot: Int, id: UUID, title: String)
        case due(id: UUID, title: String, date: Date, hasTime: Bool)

        var summary: String {
            switch self {
            case let .add(list, title, due, hasTime):
                "Add “\(title)” to \(list.title)" + (due.map { ", due " + ChatActions.dateText($0, hasTime: hasTime) } ?? "")
            case let .move(_, title, to): "Move “\(title)” to \(to.title)"
            case let .top3(slot, _, title): "Put “\(title)” in Top 3 slot \(slot)"
            case let .due(_, title, date, hasTime): "Set “\(title)” due " + ChatActions.dateText(date, hasTime: hasTime)
            }
        }
    }

    struct Plan: Equatable {
        var changes: [Change] = []
        var ignored: [Ignored] = []
    }

    /// Matches titles to open tasks (case and spacing don't matter). Unknown or ambiguous titles are ignored.
    static func plan(_ parsed: Parsed, tasks: [TaskRef]) -> Plan {
        var plan = Plan(ignored: parsed.ignored)
        let open = tasks.filter { !$0.isCompleted }
        func find(_ title: String) -> Result<TaskRef, Reason> {
            let key = normalized(title)
            let hits = open.filter { normalized($0.title) == key }
            if hits.count == 1 { return .success(hits[0]) }
            return .failure(Reason(hits.isEmpty ? "No open task with that title" : "More than one task has that title"))
        }
        for action in parsed.actions {
            switch action {
            case let .add(list, title, due, hasTime):
                plan.changes.append(.add(list: list, title: title, due: due, hasTime: hasTime))
            case let .move(title, to):
                switch find(title) {
                case let .success(t) where t.list == to && t.topSlot == nil:
                    plan.ignored.append(Ignored(line: "move | \(title) | \(to.title)", reason: "Already in \(to.title)"))
                case let .success(t): plan.changes.append(.move(id: t.id, title: t.title, to: to))
                case let .failure(r): plan.ignored.append(Ignored(line: "move | \(title) | \(to.title)", reason: r.text))
                }
            case let .top3(slot, title):
                switch find(title) {
                case let .success(t) where t.list == .parkingLot || t.list == .waitingOn:
                    plan.ignored.append(Ignored(line: "top3 | \(slot) | \(title)", reason: "\(t.list.title) items can't go in the Top 3"))
                case let .success(t): plan.changes.append(.top3(slot: slot, id: t.id, title: t.title))
                case let .failure(r): plan.ignored.append(Ignored(line: "top3 | \(slot) | \(title)", reason: r.text))
                }
            case let .due(title, date, hasTime):
                switch find(title) {
                case let .success(t): plan.changes.append(.due(id: t.id, title: t.title, date: date, hasTime: hasTime))
                case let .failure(r): plan.ignored.append(Ignored(line: "due | \(title)", reason: r.text))
                }
            }
        }
        return plan
    }

    private static func normalized(_ s: String) -> String {
        s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func dateText(_ d: Date, hasTime: Bool) -> String {
        hasTime ? d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
            : d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

// MARK: - Confirm and undo

/// The task fields an approved plan can change, captured so Undo can put them back.
struct ChatTaskFields: Equatable {
    var list: ListKind
    var position: Double
    var topSlot: Int?
    var topDay: String?
    var dueDate: Date?
    var hasDueTime: Bool
    var unscheduled: Bool
}

struct ChatUndo: Equatable {
    /// Tasks the plan added: Undo removes them.
    var created: [UUID] = []
    /// Fields of tasks the plan changed, as they were before.
    var before: [UUID: ChatTaskFields] = [:]

    var isEmpty: Bool { created.isEmpty && before.isEmpty }

    /// Only the tasks that actually changed, from snapshots taken before and after applying.
    static func diff(before: [UUID: ChatTaskFields], after: [UUID: ChatTaskFields], created: [UUID]) -> ChatUndo {
        ChatUndo(created: created, before: before.filter { id, old in after[id].map { $0 != old } ?? false })
    }
}

/// Review → Approve or Cancel → Undo for 30 seconds. Pure, so the flow is tested without the UI.
struct ChatConfirmFlow: Equatable {
    enum State: Equatable {
        case idle
        case reviewing(ChatActions.Plan)
        case applied(count: Int, until: Date)
    }

    static let undoWindow: TimeInterval = 30

    private(set) var state: State = .idle
    private(set) var undo: ChatUndo?

    var plan: ChatActions.Plan? {
        if case let .reviewing(p) = state { return p }
        return nil
    }

    mutating func review(_ plan: ChatActions.Plan) {
        state = .reviewing(plan)
        undo = nil
    }

    mutating func cancel() {
        if case .reviewing = state { state = .idle }
    }

    /// Applies the plan under review. Does nothing unless a plan with changes is being reviewed.
    @discardableResult
    mutating func approve(now: Date, apply: (ChatActions.Plan) -> ChatUndo) -> Bool {
        guard case let .reviewing(plan) = state, !plan.changes.isEmpty else { return false }
        undo = apply(plan)
        state = .applied(count: plan.changes.count, until: now.addingTimeInterval(Self.undoWindow))
        return true
    }

    func canUndo(now: Date) -> Bool {
        if case let .applied(_, until) = state { return now < until && undo != nil }
        return false
    }

    /// The record to restore, once, within the undo window.
    mutating func takeUndo(now: Date) -> ChatUndo? {
        guard canUndo(now: now) else { return nil }
        let u = undo
        undo = nil
        state = .idle
        return u
    }

    mutating func expire(now: Date) {
        if case let .applied(_, until) = state, now >= until {
            state = .idle
            undo = nil
        }
    }
}
