import SwiftData
import SwiftUI

/// Menu bar label: Top 3 progress as plain text, e.g. "2/3".
struct MenuBarLabel: View {
    let model: AppModel
    var body: some View {
        let p = model.top3Progress
        Text("\(p.done)/3").monospacedDigit().accessibilityLabel("ProTask, \(p.done) of 3 done")
    }
}

/// Menu bar dropdown: today's Top 3 with checkboxes, a quick-add field, and Open ProTask.
struct MenuBarQuickAdd: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Query private var tasks: [TaskItem]
    @State private var text = ""
    @State private var detectDates = true

    var body: some View {
        let pins = model.pinned(in: tasks)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SectionLabel(title: "Top 3")
                    Spacer()
                    Text("\(pins.values.filter(\.isCompleted).count)/3")
                        .font(Theme.Fonts.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                }
                .frame(height: Theme.Size.row)
                ForEach(Top3Planner.slots, id: \.self) { n in
                    if let t = pins[n] {
                        Button { withAnimation(Theme.Motion.list) { model.setCompleted(t, !t.isCompleted) } } label: {
                            HStack(spacing: Theme.Space.s) {
                                Checkbox(checked: t.isCompleted)
                                Text(t.title)
                                    .font(Theme.Fonts.small)
                                    .foregroundStyle(t.isCompleted ? Theme.Palette.textTertiary : Theme.Palette.text)
                                    .strikethrough(t.isCompleted, color: Theme.Palette.textTertiary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .frame(height: Theme.Size.row)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: Theme.Space.s) {
                            Text("\(n)").font(Theme.Fonts.mono).foregroundStyle(Theme.Palette.textTertiary)
                                .frame(width: Theme.Size.checkbox)
                            Text("Empty").font(Theme.Fonts.small).foregroundStyle(Theme.Palette.textTertiary)
                        }
                        .frame(height: Theme.Size.row)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.bottom, Theme.Space.s)
            Hairline()
            SmartTaskField(placeholder: "Add a task   ~ nice   ? idea", text: $text, detectDates: $detectDates,
                           leadingIcon: .add, bordered: false, focusOnAppear: true) {
                if model.capture(text, detectDates: detectDates) { text = "" }
            }
            .padding(Theme.Space.m)
            Hairline()
            HStack(spacing: 0) {
                Button("Open ProTask") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                .buttonStyle(.ghost)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.ghost)
            }
            .padding(Theme.Space.xs)
        }
        .frame(width: Theme.Size.menuBarWidth)
        .background(Theme.Palette.surface)
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showMenuBarExtra") private var showMenuBar = true
    @AppStorage("resetHour") private var resetHour = DayKey.defaultResetHour
    @AppStorage("morningPlanning") private var morningPlanning = true
    @AppStorage(AppModel.focusMinutesKey) private var focusMinutes = 25
    @AppStorage(AppModel.eveningEnabledKey) private var eveningOn = true
    @AppStorage(AppModel.eveningHourKey) private var eveningHour = 18
    @AppStorage(AppModel.eveningMinuteKey) private var eveningMinute = 0
    @State private var notificationStatus = "Checking…"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: "General").padding(.horizontal, Theme.Space.l).frame(height: Theme.Size.row)
            row("Menu bar") {
                Toggle("Show Parking Lot in the menu bar", isOn: $showMenuBar)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
            row("Quick add") {
                HotKeyRecorder()
                Text("opens from anywhere").foregroundStyle(Theme.Palette.textTertiary)
            }
            row("New day starts") {
                Menu(hourLabel(resetHour)) {
                    ForEach(0..<9) { h in Button(hourLabel(h)) { resetHour = h } }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(Theme.Fonts.small)
                .onChange(of: resetHour) { model.checkDay() }
            }
            Hairline().padding(.vertical, Theme.Space.s)
            SectionLabel(title: "Daily rhythm").padding(.horizontal, Theme.Space.l).frame(height: Theme.Size.row)
            row("Morning planning") {
                Toggle("Show the planning screen on the first open of the day", isOn: $morningPlanning)
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
            row("Evening wrap-up") {
                Toggle("Evening wrap-up reminder", isOn: $eveningOn)
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                    .onChange(of: eveningOn) { model.scheduleEveningWrapUp() }
                DatePicker("Time", selection: eveningTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .disabled(!eveningOn)
            }
            row("Focus timer") {
                Segments(options: [15, 25, 45, 50, 90], selection: $focusMinutes) { "\($0) min" }
            }
            Hairline().padding(.vertical, Theme.Space.s)
            SectionLabel(title: "Permissions").padding(.horizontal, Theme.Space.l).frame(height: Theme.Size.row)
            row("Calendar") {
                if model.calendar.hasAccess {
                    Text("Allowed").foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    AccessPrompt()
                }
            }
            row("Notifications") {
                Text(notificationStatus).foregroundStyle(Theme.Palette.textSecondary)
                Button("Open Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Palette.accent)
            }
        }
        .font(Theme.Fonts.small)
        .foregroundStyle(Theme.Palette.text)
        .padding(.vertical, Theme.Space.m)
        .frame(width: Theme.Size.settingsWidth)
        .background(Theme.Palette.background)
        .tint(Theme.Palette.accent)
        .task {
            switch await model.notifications.authorizationStatus() {
            case .authorized, .provisional: notificationStatus = "Allowed"
            case .denied: notificationStatus = "Off"
            default: notificationStatus = "Not asked yet"
            }
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Theme.Space.s) {
            Text(label)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: Theme.Size.propertyLabel + Theme.Space.xl, alignment: .leading)
            content()
            Spacer()
        }
        .padding(.horizontal, Theme.Space.l)
        .frame(height: Theme.Size.row)
    }

    private var eveningTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: eveningHour, minute: eveningMinute, second: 0, of: Date()) ?? Date()
        } set: { d in
            eveningHour = Calendar.current.component(.hour, from: d)
            eveningMinute = Calendar.current.component(.minute, from: d)
            model.scheduleEveningWrapUp()
        }
    }

    private func hourLabel(_ h: Int) -> String {
        Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date())!.formatted(date: .omitted, time: .shortened)
    }
}
