import AppKit
import EventKit
import Observation

/// One-way sync of tasks to a dedicated "ProTask" calendar, plus today's events for the side panel.
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

    /// Brings one task's event in line with the task. Updates `task.calendarEventID`.
    func sync(_ task: TaskItem, today: String) {
        guard hasAccess, let calendar = top3Calendar() else { return }
        let spec = task.isIdea ? nil : EventPlanner.spec(for: task.eventInfo, today: today)
        let existing = task.calendarEventID.flatMap { store.event(withIdentifier: $0) }

        guard let spec else {
            if let existing { remove(existing) }
            task.calendarEventID = nil
            return
        }
        let event = existing ?? EKEvent(eventStore: store)
        if existing != nil, matches(event, spec), event.calendar == calendar { return }
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
            task.calendarEventID = event.eventIdentifier
            lastError = nil
        } catch {
            lastError = "Calendar sync failed: \(error.localizedDescription)"
        }
    }

    func removeEvent(id: String?) {
        guard hasAccess, let id, let event = store.event(withIdentifier: id) else { return }
        remove(event)
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
