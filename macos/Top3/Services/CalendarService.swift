import AppKit
import EventKit
import Observation

/// Sync of tasks with a dedicated "ProTask" calendar, plus today's events for the side panel.
/// Only events in the ProTask calendar are ever created, changed or removed.
@MainActor
@Observable
final class CalendarService {
    static let calendarTitle = "ProTask"
    /// The calendar's name before the app was renamed. Found and renamed in place, so its events carry over.
    static let legacyCalendarTitle = "Top 3"
    private static let calendarIDKey = "top3CalendarIdentifier"

    struct DayEvent: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let calendarTitle: String
        let color: NSColor
    }

    @ObservationIgnored let store = EKEventStore()
    private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var todayEvents: [DayEvent] = []
    private(set) var lastError: String?
    @ObservationIgnored private var observer: NSObjectProtocol?

    var hasAccess: Bool { status == .fullAccess }

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.loadToday() }
        }
    }

    func requestAccess() async {
        if status == .notDetermined {
            do { _ = try await store.requestFullAccessToEvents() } catch { lastError = error.localizedDescription }
        }
        status = EKEventStore.authorizationStatus(for: .event)
        if hasAccess {
            store.refreshSourcesIfNecessary()
            _ = top3Calendar()
            loadToday()
        }
    }

    // MARK: ProTask calendar

    /// Finds the saved "ProTask" calendar, or one with that (or the old "Top 3") title, or creates it.
    func top3Calendar() -> EKCalendar? {
        guard hasAccess else { return nil }
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: Self.calendarIDKey), let cal = store.calendar(withIdentifier: id) {
            return migrated(cal)
        }
        let writable = store.calendars(for: .event).filter(\.allowsContentModifications)
        if let cal = writable.first(where: { $0.title == Self.calendarTitle })
            ?? writable.first(where: { $0.title == Self.legacyCalendarTitle }) {
            defaults.set(cal.calendarIdentifier, forKey: Self.calendarIDKey)
            return migrated(cal)
        }
        // Not every account can host new calendars (Google can't via EventKit), so try a few sources.
        var candidates: [EKSource] = []
        if let s = store.defaultCalendarForNewEvents?.source { candidates.append(s) }
        candidates += store.sources.filter { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") }
        candidates += store.sources.filter { $0.sourceType == .local }
        candidates += store.sources.filter { $0.sourceType == .calDAV || $0.sourceType == .exchange }
        var seen = Set<String>()
        for source in candidates where seen.insert(source.sourceIdentifier).inserted {
            let cal = EKCalendar(for: .event, eventStore: store)
            cal.title = Self.calendarTitle
            cal.cgColor = NSColor.systemGray.cgColor
            cal.source = source
            do {
                try store.saveCalendar(cal, commit: true)
                defaults.set(cal.calendarIdentifier, forKey: Self.calendarIDKey)
                lastError = nil
                return cal
            } catch {
                continue
            }
        }
        lastError = "Couldn't create a \"ProTask\" calendar. Create one in Calendar.app and it will be used."
        return nil
    }

    /// Renames the pre-rename "Top 3" calendar to "ProTask". Its events stay in it, so nothing is lost.
    private func migrated(_ cal: EKCalendar) -> EKCalendar {
        guard cal.title == Self.legacyCalendarTitle else { return cal }
        cal.title = Self.calendarTitle
        do { try store.saveCalendar(cal, commit: true) } catch { lastError = "Couldn't rename the calendar: \(error.localizedDescription)" }
        return cal
    }

    // MARK: Sync

    /// Brings a task's events (due or series, and pinned) in line with the task, one link per slot.
    func sync(_ task: TaskItem, today: String) {
        guard hasAccess, let calendar = top3Calendar() else { return }
        let specs = task.isIdea ? [:] : EventPlanner.specs(for: task.eventInfo, today: today)
        var links: [LinkSlot: EventLink] = [:]
        var events: [LinkSlot: EKEvent] = [:]
        var matching: [LinkSlot: Bool] = [:]
        for slot in LinkSlot.allCases {
            guard let link = task.link(slot) else { continue }
            links[slot] = link
            if let e = event(for: link, in: calendar) {
                events[slot] = e
                matching[slot] = specs[slot].map { matches(e, $0) } ?? false
            }
        }
        let plan = LinkSync.push(specs: specs, links: links.mapValues(\.state), remoteMatches: matching)
        for (slot, action) in plan {
            switch action {
            case .keep:
                if let spec = specs[slot], let link = links[slot], link.kind != spec.kind { link.kind = spec.kind }
            case .remove:
                if let e = events[slot] { remove(e) }
                if let link = links[slot] { unlink(link, from: task) }
            case .create, .update:
                guard let spec = specs[slot] else { continue }
                if let event = save(spec, into: events[slot] ?? EKEvent(eventStore: store), calendar: calendar) {
                    record(event, spec: spec, link: links[slot], task: task)
                }
            }
        }
    }

    /// Writes a spec to an event. Returns the saved event, or nil (and sets lastError) on failure.
    private func save(_ spec: EventSpec, into event: EKEvent, calendar: EKCalendar) -> EKEvent? {
        // Saving the first occurrence with .futureEvents edits the whole series (or collapses it when the rule goes away).
        let span: EKSpan = (event.hasRecurrenceRules || spec.recurrence != nil) ? .futureEvents : .thisEvent
        event.recurrenceRules = spec.recurrence.map { [Self.ekRule($0)] }
        event.calendar = calendar
        event.title = spec.title
        event.notes = spec.notes
        event.isAllDay = spec.isAllDay
        event.startDate = spec.start
        event.endDate = spec.end
        event.availability = spec.isAllDay ? .free : .busy
        do {
            try store.save(event, span: span, commit: true)
            lastError = nil
            return event
        } catch {
            lastError = "Calendar sync failed: \(error.localizedDescription)"
            return nil
        }
    }

    /// Remembers what was just written: identifiers, fingerprint and the event's modification time.
    private func record(_ event: EKEvent, spec: EventSpec, link: EventLink?, task: TaskItem) {
        let l = link ?? {
            let n = EventLink(kind: spec.kind, eventIdentifier: event.eventIdentifier ?? "")
            task.modelContext?.insert(n)
            n.task = task
            return n
        }()
        l.kind = spec.kind
        l.eventIdentifier = event.eventIdentifier ?? l.eventIdentifier
        l.externalIdentifier = event.calendarItemExternalIdentifier
        l.contentHash = spec.fingerprint
        l.remoteModifiedAt = event.lastModifiedDate
        l.lastSyncedAt = Date()
    }

    private func unlink(_ link: EventLink, from task: TaskItem) {
        task.links?.removeAll { $0.id == link.id }
        task.modelContext?.delete(link)
    }

    /// The linked event, only if it is still in the ProTask calendar. Falls back to the external
    /// identifier, which survives the identifier changes some accounts make when they re-sync.
    func event(for link: EventLink, in calendar: EKCalendar) -> EKEvent? {
        if let e = store.event(withIdentifier: link.eventIdentifier), e.calendar?.calendarIdentifier == calendar.calendarIdentifier {
            return e
        }
        guard let ext = link.externalIdentifier else { return nil }
        let match = store.calendarItems(withExternalIdentifier: ext).compactMap { $0 as? EKEvent }
            .first { $0.calendar?.calendarIdentifier == calendar.calendarIdentifier }
        if let match, let id = match.eventIdentifier { link.eventIdentifier = id }
        return match
    }

    /// Removes every event a task owns (before the task itself is deleted).
    func removeEvents(of task: TaskItem) {
        guard hasAccess, let calendar = top3Calendar() else { return }
        for link in task.links ?? [] {
            if let e = event(for: link, in: calendar) { remove(e) }
        }
    }

    private func remove(_ event: EKEvent) {
        do { try store.remove(event, span: event.hasRecurrenceRules ? .futureEvents : .thisEvent, commit: true) } catch { lastError = error.localizedDescription }
    }

    static func ekRule(_ r: RecurrenceRule) -> EKRecurrenceRule {
        func days(_ numbers: [Int]) -> [EKRecurrenceDayOfWeek]? {
            numbers.isEmpty ? nil : numbers.sorted().compactMap { EKWeekday(rawValue: $0).map { EKRecurrenceDayOfWeek($0) } }
        }
        let n = max(r.interval, 1)
        switch r.kind {
        case .daily: return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekdays:
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, daysOfTheWeek: days([2, 3, 4, 5, 6]),
                                    daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
        case .weekly: return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .monthly: return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .custom where r.unit == .days: return EKRecurrenceRule(recurrenceWith: .daily, interval: n, end: nil)
        case .custom:
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: n, daysOfTheWeek: days(r.weekdays),
                                    daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
        }
    }

    private func matches(_ e: EKEvent, _ s: EventSpec) -> Bool {
        let want = s.recurrence.map { Self.ekRule($0) }
        let have = e.recurrenceRules?.first
        let sameRepeat = (want == nil && have == nil)
            || (want != nil && have != nil && want!.frequency == have!.frequency && want!.interval == have!.interval
                && (want!.daysOfTheWeek?.count ?? 0) == (have!.daysOfTheWeek?.count ?? 0))
        guard sameRepeat else { return false }
        return e.title == s.title && e.notes == s.notes && e.isAllDay == s.isAllDay
            && (s.isAllDay ? Calendar.current.isDate(e.startDate, inSameDayAs: s.start) : e.startDate == s.start && e.endDate == s.end)
    }

    // MARK: Today's events

    func loadToday(now: Date = Date()) {
        status = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else { todayEvents = []; return }
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let top3ID = UserDefaults.standard.string(forKey: Self.calendarIDKey)
        let calendars = store.calendars(for: .event).filter { $0.calendarIdentifier != top3ID }
        guard !calendars.isEmpty else { todayEvents = []; return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        todayEvents = store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map {
                DayEvent(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "Busy", start: $0.startDate,
                         end: $0.endDate, isAllDay: $0.isAllDay, calendarTitle: $0.calendar.title,
                         color: NSColor(cgColor: $0.calendar.cgColor) ?? .systemGray)
            }
    }

    func freeGaps(now: Date = Date(), from startHour: Int = 8, to endHour: Int = 20) -> [DateInterval] {
        let cal = Calendar.current
        guard let s = cal.date(bySettingHour: startHour, minute: 0, second: 0, of: now),
              let e = cal.date(bySettingHour: endHour, minute: 0, second: 0, of: now) else { return [] }
        let busy = todayEvents.filter { !$0.isAllDay }.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
        return FreeTime.gaps(busy: busy, dayStart: s, dayEnd: e, now: now, minMinutes: 20)
    }
}
