import SwiftData
import SwiftUI

/// Optional menu bar item for parking ideas without opening the main window.
struct MenuBarQuickAdd: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @State private var text = ""
    @State private var saved = false

    var body: some View {
        let ideas = tasks.filter(\.isIdea).prefix(5)
        VStack(alignment: .leading, spacing: 0) {
            InputField(placeholder: "Park an idea…", text: $text, leadingIcon: .quickAdd, bordered: false,
                       focusOnAppear: true) {
                guard model.addIdea(text) else { return }
                text = ""
                withAnimation(Theme.Motion.standard) { saved = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + Theme.Motion.toastDuration / 2) {
                    withAnimation(Theme.Motion.standard) { saved = false }
                }
            }
            .padding(Theme.Space.m)
            Hairline()
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack {
                    SectionLabel(title: "Parking Lot")
                    Spacer()
                    if saved { Text("Parked").font(Theme.Fonts.caption).foregroundStyle(Theme.Palette.accent) }
                }
                .padding(.bottom, Theme.Space.xxs)
                if ideas.isEmpty {
                    Text("No parked ideas.").font(Theme.Fonts.small).foregroundStyle(Theme.Palette.textTertiary)
                }
                ForEach(Array(ideas)) { idea in
                    HStack {
                        Text(idea.title).font(Theme.Fonts.small).foregroundStyle(Theme.Palette.text).lineLimit(1)
                        Spacer()
                        Text(Fmt.time(idea.createdAt)).font(Theme.Fonts.secondary).foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
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
        .tint(Theme.Palette.accent)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showMenuBarExtra") private var showMenuBar = true
    @AppStorage("resetHour") private var resetHour = DayKey.defaultResetHour
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

    private func hourLabel(_ h: Int) -> String {
        Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date())!.formatted(date: .omitted, time: .shortened)
    }
}
