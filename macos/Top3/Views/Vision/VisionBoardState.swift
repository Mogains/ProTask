import AppKit
import Observation

/// A confirmation the Vision board is asking for.
enum VisionPrompt: Identifiable, Equatable {
    case deleteGoal(UUID)
    case deleteTimeline(UUID)

    var id: String {
        switch self {
        case let .deleteGoal(id): "goal-\(id.uuidString)"
        case let .deleteTimeline(id): "timeline-\(id.uuidString)"
        }
    }
}

/// A goal's picture shown full size.
struct ImageViewerRequest: Equatable {
    var goalID: UUID
    var imageID: UUID
}

/// A goal being added by double-clicking a lane: it exists once it has a title.
struct PendingGoal: Equatable {
    var laneID: UUID
    var day: Date
    var type: GoalType = .goal
}

/// View state for the Vision board: where it is scrolled and zoomed, which lanes are collapsed, and what is open.
/// Zoom and jump-to-today animate by stepping the scale itself, so the axis, grid and bars always move together.
/// With Reduce Motion on, they change at once.
@MainActor
@Observable
final class VisionBoardState {
    private(set) var scale = TimelineScale(origin: Date(), pointsPerDay: TimelineZoom.year.pointsPerDay)
    private(set) var trackWidth: Double = 0
    private(set) var collapsed: Set<UUID> = []
    private(set) var showArchived = false
    /// The goal open in the detail panel.
    var openGoalID: UUID? {
        didSet {
            guard openGoalID != oldValue else { return }
            if let v = viewer, v.goalID != openGoalID { viewer = nil }
            if linkPicker != nil { linkPicker = nil }
        }
    }
    /// The full-size image viewer over the board.
    var viewer: ImageViewerRequest?
    /// The link picker sheet for the open goal.
    var linkPicker: LinkPickerKind?
    var renamingTimelineID: UUID?
    var prompt: VisionPrompt?
    var pending: PendingGoal?
    /// Bumped to hand keyboard focus back to the board.
    private(set) var focusRequest = 0

    /// Where a pinch, drag or scroll started.
    @ObservationIgnored var gestureStart: TimelineScale?
    @ObservationIgnored private var animation: Timer?
    /// Nil on throwaway runs (TOP3_STORE_PATH), so tests and screenshots never write real preferences.
    @ObservationIgnored private let defaults: UserDefaults?

    private static let zoomKey = "visionPointsPerDay"
    private static let collapsedKey = "visionCollapsedTimelines"
    private static let archivedKey = "visionShowArchived"

    init() {
        defaults = ProcessInfo.processInfo.environment["TOP3_STORE_PATH"] == nil ? .standard : nil
        if let ppd = defaults?.object(forKey: Self.zoomKey) as? Double {
            scale = TimelineScale(origin: Date(), pointsPerDay: ppd)
        }
        collapsed = Set((defaults?.stringArray(forKey: Self.collapsedKey) ?? []).compactMap(UUID.init(uuidString:)))
        showArchived = defaults?.bool(forKey: Self.archivedKey) ?? false
    }

    nonisolated static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var zoom: TimelineZoom { scale.zoom }

    private var bounds: DateInterval {
        let cal = Calendar.current
        let now = Date()
        let years = Theme.Timeline.panYears
        return DateInterval(start: cal.date(byAdding: .year, value: -years, to: now) ?? now,
                            end: cal.date(byAdding: .year, value: years, to: now) ?? now)
    }

    // MARK: Size

    /// Called with the track's width on layout. The first time, today goes a little left of center.
    func updateWidth(_ width: Double) {
        guard width > 0, width != trackWidth else { return }
        let first = trackWidth == 0
        trackWidth = width
        if first {
            scale = .placing(Date(), atFraction: Theme.Timeline.todayFraction, width: width, pointsPerDay: scale.pointsPerDay)
        }
    }

    // MARK: Moving the view

    /// Sets the view at once (pinch, scroll, drag), within ±100 years of today.
    func setScale(_ s: TimelineScale) {
        stopAnimation()
        scale = s.clamped(to: bounds, width: trackWidth)
    }

    func pan(by dx: Double) { setScale(scale.panned(by: dx)) }

    /// Moves to `target`, animated unless Reduce Motion is on. `anchorX` is the point that stays put while zooming.
    func move(to target: TimelineScale, anchorX: Double? = nil, reduceMotion: Bool = VisionBoardState.reduceMotion) {
        let target = target.clamped(to: bounds, width: trackWidth)
        stopAnimation()
        guard !reduceMotion, trackWidth > 0, target != scale else {
            scale = target
            saveZoom()
            return
        }
        let from = scale
        let anchor = anchorX ?? trackWidth / 2
        let start = ProcessInfo.processInfo.systemUptime
        let duration = Theme.Motion.timelineDuration
        let timer = Timer(timeInterval: Theme.Motion.timelineFrame, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                let t = (ProcessInfo.processInfo.systemUptime - start) / duration
                self.scale = TimelineScale.interpolate(from: from, to: target, anchorX: anchor, progress: TimelineScale.easeOut(t))
                if t >= 1 {
                    self.stopAnimation()
                    self.saveZoom()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animation = timer
    }

    private func stopAnimation() {
        animation?.invalidate()
        animation = nil
    }

    func zoom(to ppd: Double, anchorX: Double? = nil, reduceMotion: Bool = VisionBoardState.reduceMotion) {
        let anchor = anchorX ?? trackWidth / 2
        move(to: scale.zoomed(to: ppd, anchorX: anchor), anchorX: anchor, reduceMotion: reduceMotion)
    }

    func setZoom(_ level: TimelineZoom, reduceMotion: Bool = VisionBoardState.reduceMotion) {
        zoom(to: level.pointsPerDay, reduceMotion: reduceMotion)
    }

    func zoomIn(reduceMotion: Bool = VisionBoardState.reduceMotion) {
        zoom(to: TimelineZoom.zoomedIn(from: scale.pointsPerDay), reduceMotion: reduceMotion)
    }

    func zoomOut(reduceMotion: Bool = VisionBoardState.reduceMotion) {
        zoom(to: TimelineZoom.zoomedOut(from: scale.pointsPerDay), reduceMotion: reduceMotion)
    }

    func goToToday(reduceMotion: Bool = VisionBoardState.reduceMotion) {
        let target = TimelineScale.placing(Date(), atFraction: Theme.Timeline.todayFraction, width: trackWidth,
                                           pointsPerDay: scale.pointsPerDay)
        move(to: target, anchorX: 0, reduceMotion: reduceMotion)
    }

    /// Pans just enough to show these days.
    func reveal(_ span: DaySpan, reduceMotion: Bool = VisionBoardState.reduceMotion) {
        let end = span.visualEnd(calendar: .current)
        let target = scale.revealing(start: span.start, end: end, width: trackWidth, padding: Theme.Timeline.revealPadding)
        if target != scale { move(to: target, anchorX: 0, reduceMotion: reduceMotion) }
    }

    /// Remembers the zoom level for next time (after a gesture or animation settles).
    func saveZoom() {
        defaults?.set(scale.pointsPerDay, forKey: Self.zoomKey)
    }

    // MARK: Lanes

    func isCollapsed(_ id: UUID) -> Bool { collapsed.contains(id) }

    func toggleCollapsed(_ id: UUID) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        defaults?.set(collapsed.map(\.uuidString).sorted(), forKey: Self.collapsedKey)
    }

    func setShowArchived(_ on: Bool) {
        showArchived = on
        defaults?.set(on, forKey: Self.archivedKey)
    }

    func requestFocus() { focusRequest += 1 }

    /// Closes whatever is open on the board: the image viewer, the inline prompt, a rename, then the detail panel.
    /// Returns false when there was nothing to close.
    @discardableResult
    func dismissTop() -> Bool {
        if viewer != nil { viewer = nil; return true }
        if pending != nil { pending = nil; return true }
        if renamingTimelineID != nil { renamingTimelineID = nil; return true }
        if openGoalID != nil { openGoalID = nil; return true }
        return false
    }
}
