import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    let tasks: [TaskItem]
    @Query private var logs: [DayLog]

    var body: some View {
        let pins = model.pinned(in: tasks)
        let haveTo = model.ordered(.haveTo, in: tasks)
        let niceTo = model.ordered(.niceTo, in: tasks)
        let promptDismissed = logs.first { $0.day == model.today }?.promptDismissed ?? false
        let showPrompt = pins.isEmpty && !promptDismissed && !(haveTo.isEmpty && niceTo.isEmpty)

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                if showPrompt { prompt }
                Top3Block(pins: pins)
                let offCalendar = tasks.filter { $0.unscheduled && !$0.isCompleted }
                if !offCalendar.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel(title: "Removed from your calendar", detail: "\(offCalendar.count)")
                        .padding(.leading, Theme.Space.s)
                        .frame(height: Theme.Size.row)
                        ForEach(offCalendar) { t in
                            HStack(spacing: Theme.Space.s) {
                                TaskRow(task: t, showDivider: t.id != offCalendar.last?.id, showHandle: false)
                                Button("Put back") { withAnimation(Theme.Motion.standard) { model.putBackOnCalendar(t) } }
                                    .buttonStyle(.ghost)
                                    .help("Create its calendar event again")
                            }
                        }
                    }
                }
                let followUps = tasks.filter { model.isFollowUpDue($0) }
                if !followUps.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel(title: "Follow up", detail: "\(followUps.count)")
                            .padding(.leading, Theme.Space.s)
                            .frame(height: Theme.Size.row)
                        ForEach(followUps) { TaskRow(task: $0, showDivider: $0.id != followUps.last?.id, showHandle: false) }
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Theme.Space.xl) {
                        TaskColumn(list: .haveTo, tasks: haveTo)
                        TaskColumn(list: .niceTo, tasks: niceTo)
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.xl) {
                        TaskColumn(list: .haveTo, tasks: haveTo)
                        TaskColumn(list: .niceTo, tasks: niceTo)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.l)
        }
        .scrollIndicators(.automatic)
    }

    private var prompt: some View {
        HStack(spacing: Theme.Space.s) {
            Text("New day. Pick your Top 3: drag tasks into the slots, click a star, or select one and press ⌘1, ⌘2 or ⌘3.")
                .font(Theme.Fonts.small)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Button("Dismiss") { withAnimation(Theme.Motion.standard) { model.dismissPrompt() } }
                .buttonStyle(.ghost)
        }
    }
}

/// Header accessory for Today: streak and completion as one muted line.
struct TodayStats: View {
    @Environment(AppModel.self) private var model
    let tasks: [TaskItem]
    @Query(filter: #Predicate<DayLog> { $0.top3Complete }) private var completeDays: [DayLog]

    var body: some View {
        let stats = DailyStats.completion(tasks.map(\.statInfo), today: model.today, resetHour: model.resetHour)
        let streak = DayKey.streak(completeDays: Set(completeDays.map(\.day)), today: model.today)
        HStack(spacing: Theme.Space.m) {
            Text(streak == 1 ? "1-day streak" : "\(streak)-day streak")
                .help("Days in a row with all of your Top 3 done")
            if stats.total > 0 {
                Text("\(Int((stats.fraction * 100).rounded()))% today")
                    .help("\(stats.done) of \(stats.total) done today")
            }
        }
        .font(Theme.Fonts.secondary)
        .foregroundStyle(Theme.Palette.textTertiary)
        .monospacedDigit()
    }
}

struct Top3Block: View {
    @Environment(AppModel.self) private var model
    let pins: [Int: TaskItem]

    var body: some View {
        let done = pins.values.filter(\.isCompleted).count
        let allDone = pins.count == 3 && done == 3
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                SectionLabel(title: "Top 3")
                HStack(spacing: Theme.Space.xxs) {
                    ForEach(Top3Planner.slots, id: \.self) { n in
                        Capsule()
                            .fill(n <= done ? Theme.Palette.accent : Theme.Palette.border)
                            .frame(width: Theme.Size.progressSegment, height: Theme.Size.indicator)
                    }
                }
                Text("\(done)/3")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(allDone ? Theme.Palette.accent : Theme.Palette.textTertiary)
                    .monospacedDigit()
                if allDone {
                    Text("All done").font(Theme.Fonts.caption).foregroundStyle(Theme.Palette.accent)
                }
            }
            .padding(.leading, Theme.Space.s)
            .animation(Theme.Motion.standard, value: done)

            VStack(spacing: 0) {
                ForEach(Top3Planner.slots, id: \.self) { n in
                    Top3Slot(number: n, task: pins[n])
                    if n < Top3Planner.slots.count { Hairline() }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m)
                .strokeBorder(model.celebrating ? Theme.Palette.accent : Theme.Palette.border, lineWidth: Theme.Size.hairline))
            .animation(Theme.Motion.standard, value: model.celebrating)
        }
    }
}

struct Top3Slot: View {
    @Environment(AppModel.self) private var model
    let number: Int
    let task: TaskItem?
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 0) {
            Text("\(number)")
                .font(Theme.Fonts.mono)
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: Theme.Size.slotNumber)
                .padding(.leading, Theme.Space.m)
            if let task {
                TaskRow(task: task, inTopSlot: true, showDivider: false, showHandle: false)
                    .draggable(TaskRef(id: task.id)) { DragPreview(title: task.title) }
            } else {
                Text("Empty. Drop a task here or press ⌘\(number).")
                    .font(Theme.Fonts.small)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .padding(.leading, Theme.Space.s)
                Spacer()
            }
        }
        .frame(height: Theme.Size.row + Theme.Space.xs)
        .background(targeted ? Theme.Palette.selected : .clear)
        .contentShape(Rectangle())
        .dropDestination(for: TaskRef.self) { items, _ in
            guard let ref = items.first else { return false }
            withAnimation(Theme.Motion.list) { model.pin(ref.id, slot: number) }
            return true
        } isTargeted: { on in
            withAnimation(Theme.Motion.hover) { targeted = on }
        }
    }
}
