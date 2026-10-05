import EventKit
import SwiftUI

/// Compact timeline of today's events and free time.
struct CalendarAgenda: View {
    @Environment(AppModel.self) private var model
    var compact = true

    var body: some View {
        let cal = model.calendar
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if !cal.hasAccess {
                AccessPrompt()
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    SectionLabel(title: "Events", detail: cal.todayEvents.isEmpty ? nil : "\(cal.todayEvents.count)")
                        .padding(.bottom, Theme.Space.xs)
                    if cal.todayEvents.isEmpty {
                        Text("Nothing scheduled.").font(Theme.Fonts.small).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    ForEach(cal.todayEvents) { TimelineRow(event: $0, compact: compact) }
                }
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    SectionLabel(title: "Free", detail: "8 AM – 8 PM").padding(.bottom, Theme.Space.xs)
                    let gaps = cal.freeGaps()
                    if gaps.isEmpty {
                        Text("No free blocks left.").font(Theme.Fonts.small).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    ForEach(gaps, id: \.start) { g in
                        HStack(spacing: Theme.Space.s) {
                            Text("\(Fmt.time(g.start)) – \(Fmt.time(g.end))")
                                .font(Theme.Fonts.mono)
                                .foregroundStyle(Theme.Palette.textSecondary)
                            Spacer()
                            Text(Fmt.minutes(Int(g.duration / 60)) ?? "")
                                .font(Theme.Fonts.secondary)
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                }
                if let err = cal.lastError {
                    Text(err).font(Theme.Fonts.secondary).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
    }
}

struct TimelineRow: View {
    let event: CalendarService.DayEvent
    var compact: Bool

    var body: some View {
        let past = !event.isAllDay && event.end < Date()
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(event.isAllDay ? "All day" : Fmt.time(event.start))
                .font(Theme.Fonts.mono)
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: Theme.Size.timeColumn, alignment: .leading)
            RoundedRectangle(cornerRadius: Theme.Size.hairline)
                .fill(Color(nsColor: event.color))
                .frame(width: Theme.Size.marker, height: Theme.Size.eventMarkerHeight)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Theme.Space.xs }
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(event.title)
                    .font(Theme.Fonts.small)
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(compact ? 1 : 2)
                if !compact {
                    Text(event.isAllDay ? event.calendarTitle : "\(Fmt.time(event.start)) – \(Fmt.time(event.end)) · \(event.calendarTitle)")
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Space.xxs)
        .opacity(past ? Theme.Opacity.past : 1)
    }
}

/// One muted line with a small text link.
struct AccessPrompt: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Text("Calendar is off.").foregroundStyle(Theme.Palette.textTertiary)
            Button(model.calendar.status == .notDetermined ? "Enable" : "Open Settings") {
                if model.calendar.status == .notDetermined {
                    Task { await model.requestCalendarAccess() }
                } else {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Palette.accent)
        }
        .font(Theme.Fonts.small)
    }
}

struct CalendarPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Today").font(Theme.Fonts.smallMedium).foregroundStyle(Theme.Palette.text)
                Spacer()
                Text(Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(.horizontal, Theme.Space.l)
            .frame(height: Theme.Size.header)
            .background(WindowDragArea())
            Hairline()
            ScrollView {
                CalendarAgenda(compact: true)
                    .padding(Theme.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct CalendarScreen: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                CalendarAgenda(compact: false)
                if model.calendar.hasAccess, let cal = model.calendar.top3Calendar() {
                    Text("Tasks with a due date and today's Top 3 are added to the \"\(cal.title)\" calendar in \(cal.source.title). Changes go one way, from ProTask to your calendar.")
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.l)
            .frame(maxWidth: Theme.Size.contentMaxWidth, alignment: .leading)
        }
    }
}
