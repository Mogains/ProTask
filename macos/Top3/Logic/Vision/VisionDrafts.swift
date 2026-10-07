import Foundation

/// The editable fields of a timeline, before they are saved.
struct TimelineDraft: Equatable {
    var name: String
    var details: String = ""
    var color: TimelineColor = .fallback

    init(name: String, details: String = "", color: TimelineColor = .fallback) {
        self.name = name
        self.details = details
        self.color = color
    }

    init(template: TimelineTemplate) {
        self.init(name: template.name, details: template.details, color: template.color)
    }

    /// Trimmed, or nil when there is no name.
    func normalized() -> TimelineDraft? {
        var d = self
        d.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        d.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return d.name.isEmpty ? nil : d
    }
}

/// The editable fields of a goal, before they are saved.
struct GoalDraft: Equatable {
    var title: String
    var notes: String = ""
    var timelineID: UUID
    var type: GoalType = .goal
    var status: GoalStatus = .planned
    var startDate: Date?
    var targetDate: Date?
    var progress: Int = 0
    var progressMode: ProgressMode = .manual
    var metric: GoalMetric?
    var syncTargetToCalendar = false

    /// Trimmed, progress clamped to 0-100, a target before the start swapped into order,
    /// and a metric with non-finite numbers dropped. Nil when there is no title.
    func normalized() -> GoalDraft? {
        var d = self
        d.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        d.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !d.title.isEmpty else { return nil }
        d.progress = GoalProgress.clamp(progress)
        if let s = startDate, let t = targetDate, t < s {
            d.startDate = t
            d.targetDate = s
        }
        if var m = metric {
            m.name = m.name.trimmingCharacters(in: .whitespacesAndNewlines)
            m.unit = m.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            d.metric = m.isValid ? m : nil
        }
        return d
    }
}

/// Manual order for timelines, goals and images: evenly spaced sort keys, lower first.
enum VisionOrder {
    static let step: Double = 1000

    /// Sort keys for items in this order.
    static func keys(count: Int) -> [Double] { (0..<max(count, 0)).map { Double($0 + 1) * step } }

    /// A key after every existing one.
    static func end(after keys: [Double]) -> Double { (keys.max() ?? 0) + step }

    /// `ids` with `id` moved in front of `beforeID` (or to the end when nil or not found).
    static func moving(_ id: UUID, before beforeID: UUID?, in ids: [UUID]) -> [UUID] {
        guard id != beforeID else { return ids }
        var out = ids.filter { $0 != id }
        let index = beforeID.flatMap { out.firstIndex(of: $0) } ?? out.count
        out.insert(id, at: index)
        return out
    }
}
