import SwiftData
import SwiftUI

/// Weekly review: plain text and numbers, plus one grey sparkline of the week's completions.
struct ReviewView: View {
    @Environment(AppModel.self) private var model
    let tasks: [TaskItem]
    @Query private var sessions: [FocusSession]
    @Query(filter: #Predicate<DayLog> { $0.top3Complete }) private var completeDays: [DayLog]

    var body: some View {
        let cal = Calendar.current
        let week = WeeklyStats.weekInterval(containing: Date(), calendar: cal)
        let real = tasks.filter { !$0.isIdea }
        let input = WeeklyStats.Input(
            completedAt: real.compactMap { $0.isCompleted ? $0.completedAt : nil },
            openDue: real.filter { !$0.isCompleted }.compactMap(\.dueDate),
            focusSessions: sessions.map { ($0.start, $0.seconds) },
            estimateVsActual: real.filter { t in
                t.isCompleted && (t.completedAt.map { week.contains($0) } ?? false) && (t.estimateMinutes ?? 0) > 0 && t.actualSeconds > 0
            }.map { ($0.estimateMinutes!, $0.actualSeconds) },
            completeTop3Days: Set(completeDays.map(\.day)))
        let r = WeeklyStats.compute(input, now: Date(), calendar: cal)
        let streak = DayKey.streak(completeDays: Set(completeDays.map(\.day)), today: model.today)

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: 0) {
                    stat("Completed this week", "\(r.completedThisWeek)", note: "last week \(r.completedLastWeek)")
                    stat("Completion rate", r.completionRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                         note: "done ÷ (done + open due this week)")
                    stat("Current streak", streak == 1 ? "1 day" : "\(streak) days")
                    stat("Focus time", Fmt.minutes(r.focusSeconds / 60) ?? "0m")
                    stat("Actual vs estimated", r.actualToEstimate.map { String(format: "%.2f×", $0) } ?? "—",
                         note: r.actualToEstimate.map { $0 > 1 ? "tasks took longer than planned" : "tasks took less than planned" })
                    stat("Top 3 days fully done", "\(r.fullTop3Days) of 7", last: true)
                }

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionLabel(title: "Completed per day")
                    Sparkline(values: r.perDay, labels: (0..<7).map { i in
                        let d = cal.date(byAdding: .day, value: i, to: week.start)!
                        return String(d.formatted(.dateTime.weekday(.narrow)))
                    })
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.l)
            .frame(maxWidth: Theme.Size.contentMaxWidth, alignment: .leading)
        }
    }

    private func stat(_ label: String, _ value: String, note: String? = nil, last: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(label).font(Theme.Fonts.body).foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            if let note { Text(note).font(Theme.Fonts.secondary).foregroundStyle(Theme.Palette.textTertiary) }
            Text(value).font(Theme.Fonts.bodyMedium).foregroundStyle(Theme.Palette.text).monospacedDigit()
                .frame(minWidth: Theme.Size.timeColumn, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Space.s)
        .frame(height: Theme.Size.row)
        .overlay(alignment: .bottom) { if !last { Hairline() } }
    }
}

/// Seven minimal grey bars; the best day is highlighted in the accent.
struct Sparkline: View {
    let values: [Int]
    let labels: [String]

    var body: some View {
        let top = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: Theme.Space.s) {
            ForEach(values.indices, id: \.self) { i in
                VStack(spacing: Theme.Space.xs) {
                    Text("\(values[i])").font(Theme.Fonts.caption).foregroundStyle(Theme.Palette.textTertiary)
                    RoundedRectangle(cornerRadius: Theme.Size.hairline)
                        .fill(values[i] == 0 ? Theme.Palette.subtle : values[i] == top ? Theme.Palette.accent : Theme.Palette.textTertiary)
                        .frame(width: Theme.Size.sparkBar,
                               height: max(Theme.Size.hairline * 2, Theme.Size.sparkHeight * CGFloat(values[i]) / CGFloat(top)))
                    Text(labels[i]).font(Theme.Fonts.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
        .frame(height: Theme.Size.sparkHeight + Theme.Space.xxl, alignment: .bottom)
    }
}
