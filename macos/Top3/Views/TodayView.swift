import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    let tasks: [TaskItem]
    @Query(filter: #Predicate<DayLog> { $0.top3Complete }) private var completeDays: [DayLog]
    @Query private var logs: [DayLog]

    var body: some View {
        let pins = model.pinned(in: tasks)
        let haveTo = model.ordered(.haveTo, in: tasks)
        let niceTo = model.ordered(.niceTo, in: tasks)
        let promptDismissed = logs.first { $0.day == model.today }?.promptDismissed ?? false
        let showPrompt = pins.isEmpty && !promptDismissed && !(haveTo.isEmpty && niceTo.isEmpty)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if showPrompt { prompt }
                Top3Slots(pins: pins)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        TaskColumn(list: .haveTo, tasks: haveTo).frame(minWidth: 260)
                        TaskColumn(list: .niceTo, tasks: niceTo).frame(minWidth: 260)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        TaskColumn(list: .haveTo, tasks: haveTo)
                        TaskColumn(list: .niceTo, tasks: niceTo)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var header: some View {
        let stats = DailyStats.completion(tasks.map(\.statInfo), today: model.today, resetHour: model.resetHour)
        let streak = DayKey.streak(completeDays: Set(completeDays.map(\.day)), today: model.today)
        let date = DayKey.date(from: model.today) ?? Date()
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today").font(Theme.title)
                Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(Theme.secondary).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "flame")
                    Text("\(streak)-day streak").contentTransition(.numericText())
                }
                .help("Days in a row with all of your Top 3 done")
                HStack(spacing: 6) {
                    ProgressView(value: stats.fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 70)
                        .tint(.accentColor)
                    Text(stats.total == 0 ? "No tasks due" : "\(Int((stats.fraction * 100).rounded()))% today")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .help("\(stats.done) of \(stats.total) done today")
            }
            .font(Theme.secondary)
            .foregroundStyle(.secondary)
        }
    }

    private var prompt: some View {
        HStack(spacing: 10) {
            Image(systemName: "sunrise").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("New day. Pick your Top 3.").font(Theme.bodyMedium)
                Text("Drag tasks into the slots, click a star, or select a task and press Command-1, 2 or 3. Yesterday's unfinished picks are back in their lists.")
                    .font(Theme.secondary).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Dismiss") { model.dismissPrompt() }.controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.rowHover))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline))
    }
}

struct Top3Slots: View {
    @Environment(AppModel.self) private var model
    let pins: [Int: TaskItem]

    var body: some View {
        let done = pins.values.filter(\.isCompleted).count
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Top 3", detail: pins.isEmpty ? nil : "\(done) of \(pins.count) done")
                .padding(.horizontal, 8)
            VStack(spacing: 0) {
                ForEach(Top3Planner.slots, id: \.self) { n in
                    Top3Slot(number: n, task: pins[n])
                    if n < 3 { Divider().opacity(0.6) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.rowHover.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline))
        }
    }
}

struct Top3Slot: View {
    @Environment(AppModel.self) private var model
    let number: Int
    let task: TaskItem?
    @State private var targeted = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(number)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(Circle().strokeBorder(Theme.hairline))
                .padding(.top, 5)
            if let task {
                TaskRow(task: task, inTopSlot: true)
                    .draggable(TaskRef(id: task.id)) { DragPreview(title: task.title) }
            } else {
                Text("Drag a task here, or select one and press Command-\(number)")
                    .font(Theme.secondary)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 8)
                Spacer()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(minHeight: 36)
        .background(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 1).opacity(targeted ? 1 : 0))
        .contentShape(Rectangle())
        .dropDestination(for: TaskRef.self) { items, _ in
            guard let ref = items.first else { return false }
            withAnimation(.snappy) { model.pin(ref.id, slot: number) }
            return true
        } isTargeted: { targeted = $0 }
    }
}
