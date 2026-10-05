import EventKit
import SwiftUI

/// Today's events and free time. Used in the side panel (compact) and the Calendar section.
struct CalendarAgenda: View {
    @Environment(AppModel.self) private var model
    var compact = true

    var body: some View {
        let cal = model.calendar
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            if !cal.hasAccess {
                AccessPrompt()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Events", detail: cal.todayEvents.isEmpty ? nil : "\(cal.todayEvents.count)")
                    if cal.todayEvents.isEmpty {
                        Text("Nothing scheduled today.").font(Theme.secondary).foregroundStyle(.secondary)
                    }
                    ForEach(cal.todayEvents) { e in EventRow(event: e, compact: compact) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Free time", detail: "8 AM to 8 PM")
                    let gaps = cal.freeGaps()
                    if gaps.isEmpty {
                        Text("No free blocks left today.").font(Theme.secondary).foregroundStyle(.secondary)
                    }
                    ForEach(gaps, id: \.start) { g in
                        HStack {
                            Text("\(Fmt.time(g.start)) – \(Fmt.time(g.end))").monospacedDigit()
                            Spacer()
                            Text(Fmt.minutes(Int(g.duration / 60)) ?? "").foregroundStyle(.secondary)
                        }
                        .font(Theme.secondary)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.hairline))
                    }
                }
                if let err = cal.lastError {
                    Label(err, systemImage: "exclamationmark.triangle").font(Theme.secondary).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct EventRow: View {
    let event: CalendarService.DayEvent
    var compact: Bool
    var body: some View {
        let past = !event.isAllDay && event.end < Date()
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 1).fill(Color(nsColor: event.color).opacity(0.55)).frame(width: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(Theme.secondary.weight(.medium)).lineLimit(compact ? 1 : 2)
                Text(event.isAllDay ? "All day" : "\(Fmt.time(event.start)) – \(Fmt.time(event.end))")
                    .font(Theme.caption).foregroundStyle(.secondary).monospacedDigit()
                if !compact { Text(event.calendarTitle).font(Theme.caption).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .opacity(past ? 0.45 : 1)
    }
}

struct AccessPrompt: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calendar access is off").font(Theme.bodyMedium)
            Text("Allow access to see today's events and to add tasks with due dates to a \"Top 3\" calendar.")
                .font(Theme.secondary).foregroundStyle(.secondary)
            if model.calendar.status == .notDetermined {
                Button("Allow Calendar Access") { Task { await model.requestCalendarAccess() } }.controlSize(.small)
            } else {
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
                .controlSize(.small)
            }
        }
    }
}

struct CalendarPanel: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Today").font(Theme.bodyMedium)
                CalendarAgenda(compact: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CalendarScreen: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calendar").font(Theme.title)
                        Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(Theme.secondary).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.calendar.hasAccess {
                        Button("Sync Now") { model.syncAllEvents() }.controlSize(.small)
                        Button("Open Calendar") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
                        }
                        .controlSize(.small)
                    }
                }
                CalendarAgenda(compact: false)
                if model.calendar.hasAccess, let cal = model.calendar.top3Calendar() {
                    Text("Tasks with a due date and today's Top 3 are added to the \"\(cal.title)\" calendar in \(cal.source.title). Changes go one way, from this app to your calendar.")
                        .font(Theme.secondary).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }
}
