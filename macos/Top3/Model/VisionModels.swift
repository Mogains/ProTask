import Foundation
import SwiftData

// Vision: long-range goals on timelines. Private to this Mac: never shared, synced, uploaded or logged.
// Models point at each other by UUID (no SwiftData relationships); AppModel+Vision removes dependents explicitly.

/// One timeline on the Vision board (Career, Health, a project). Goals join it through `Goal.timelineID`.
@Model
final class VisionTimeline {
    var id: UUID = UUID()
    var name: String = ""
    /// What the timeline is about. Named `details` because `description` clashes with the persistence layer.
    var details: String = ""
    /// A TimelineColor name from the muted palette, never a hex value.
    var colorRaw: String = TimelineColor.fallback.rawValue
    /// Manual order (lower first).
    var sortOrder: Double = 0
    var archived: Bool = false
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init(name: String, details: String = "", color: TimelineColor, sortOrder: Double) {
        self.name = name
        self.details = details
        self.colorRaw = color.rawValue
        self.sortOrder = sortOrder
    }

    var color: TimelineColor {
        get { TimelineColor(named: colorRaw) }
        set { colorRaw = newValue.rawValue }
    }
}

/// A goal, milestone or habit target on a timeline.
/// Links: other goals through GoalDependency, tasks through TaskItem.goalID, routines through their own goalID.
@Model
final class Goal {
    var id: UUID = UUID()
    var timelineID: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var typeRaw: String = GoalType.goal.rawValue
    var statusRaw: String = GoalStatus.planned.rawValue
    var startDate: Date?
    var targetDate: Date?
    /// The manually set progress, 0-100. Automatic mode falls back to it when nothing can be measured.
    var progress: Int = 0
    var progressModeRaw: String = ProgressMode.manual.rawValue
    /// Optional metric: present when start, current and target are all set.
    var metricName: String = ""
    var metricStart: Double?
    var metricCurrent: Double?
    var metricTarget: Double?
    var metricUnit: String = ""
    /// The GoalImage shown on the goal's card.
    var coverImageID: UUID?
    /// Manual order within its timeline (lower first).
    var sortOrder: Double = 0
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    /// Put the target date on the ProTask calendar (used by a later phase).
    var syncTargetToCalendar: Bool = false

    init(title: String, timelineID: UUID, sortOrder: Double) {
        self.title = title
        self.timelineID = timelineID
        self.sortOrder = sortOrder
    }

    var type: GoalType {
        get { GoalType(rawValue: typeRaw) ?? .goal }
        set { typeRaw = newValue.rawValue }
    }

    var status: GoalStatus {
        get { GoalStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    var progressMode: ProgressMode {
        get { ProgressMode(rawValue: progressModeRaw) ?? .manual }
        set { progressModeRaw = newValue.rawValue }
    }

    var metric: GoalMetric? {
        get {
            guard let start = metricStart, let current = metricCurrent, let target = metricTarget else { return nil }
            return GoalMetric(name: metricName, start: start, current: current, target: target, unit: metricUnit)
        }
        set {
            metricName = newValue?.name ?? ""
            metricStart = newValue?.start
            metricCurrent = newValue?.current
            metricTarget = newValue?.target
            metricUnit = newValue?.unit ?? ""
        }
    }

    var draft: GoalDraft {
        GoalDraft(title: title, notes: notes, timelineID: timelineID, type: type, status: status, startDate: startDate,
                  targetDate: targetDate, progress: progress, progressMode: progressMode, metric: metric,
                  syncTargetToCalendar: syncTargetToCalendar)
    }
}

/// A dated progress note on a goal, with the progress and metric value at the time.
@Model
final class GoalLog {
    var id: UUID = UUID()
    var goalID: UUID = UUID()
    /// The day the entry is about.
    var date: Date = Date()
    var text: String = ""
    /// Effective progress (0-100) when the entry was written.
    var progress: Int?
    /// The metric's current value when the entry was written.
    var metricValue: Double?
    var createdAt: Date = Date()

    init(goalID: UUID, date: Date, text: String) {
        self.goalID = goalID
        self.date = date
        self.text = text
    }
}

/// A picture on a goal. The files live in the VisionImages folder (VisionImageStore); only their names are stored.
@Model
final class GoalImage {
    var id: UUID = UUID()
    var goalID: UUID = UUID()
    /// Plain file names inside VisionImages, never paths.
    var fileName: String = ""
    var thumbnailFileName: String = ""
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var caption: String = ""
    var sortOrder: Double = 0
    var createdAt: Date = Date()

    init(id: UUID, goalID: UUID, fileName: String, thumbnailFileName: String, pixelWidth: Int, pixelHeight: Int, sortOrder: Double) {
        self.id = id
        self.goalID = goalID
        self.fileName = fileName
        self.thumbnailFileName = thumbnailFileName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.sortOrder = sortOrder
    }

    var fileNames: [String] { [fileName, thumbnailFileName].filter { !$0.isEmpty } }
}

/// `downstreamID` depends on `upstreamID`: the upstream goal has to come first.
@Model
final class GoalDependency {
    var id: UUID = UUID()
    var upstreamID: UUID = UUID()
    var downstreamID: UUID = UUID()
    var createdAt: Date = Date()

    init(upstreamID: UUID, downstreamID: UUID) {
        self.upstreamID = upstreamID
        self.downstreamID = downstreamID
    }

    var edge: GoalEdge { GoalEdge(upstream: upstreamID, downstream: downstreamID) }
}
