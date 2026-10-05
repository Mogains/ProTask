import SwiftData
import SwiftUI

/// Optional menu bar item for parking ideas without opening the main window.
struct MenuBarQuickAdd: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @State private var text = ""
    @State private var saved = false
    @FocusState private var focused: Bool

    var body: some View {
        let ideas = tasks.filter(\.isIdea).prefix(5)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Parking Lot").font(Theme.sectionHeader).foregroundStyle(.secondary)
                Spacer()
                if saved {
                    Label("Parked", systemImage: "checkmark").font(Theme.caption).foregroundStyle(.secondary).transition(.opacity)
                }
            }
            TextField("Park an idea and press Return", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(Theme.body)
                .focused($focused)
                .onSubmit {
                    guard model.addIdea(text) else { return }
                    text = ""
                    withAnimation { saved = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { saved = false } }
                }
            if !ideas.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(ideas)) { idea in
                        HStack {
                            Text(idea.title).lineLimit(1)
                            Spacer()
                            Text(Fmt.time(idea.createdAt)).foregroundStyle(.tertiary)
                        }
                        .font(Theme.secondary)
                    }
                }
            }
            Divider()
            HStack {
                Button("Open Top 3") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(Theme.secondary)
        }
        .padding(12)
        .frame(width: 290)
        .onAppear { focused = true }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showMenuBarExtra") private var showMenuBar = true
    @AppStorage("resetHour") private var resetHour = DayKey.defaultResetHour
    @State private var notificationStatus = "Checking…"

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show Parking Lot in the menu bar", isOn: $showMenuBar)
                Picker("New day starts at", selection: $resetHour) {
                    ForEach(0..<9) { h in
                        Text(Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date())!
                            .formatted(date: .omitted, time: .shortened)).tag(h)
                    }
                }
                .onChange(of: resetHour) { model.checkDay() }
            }
            Section("Permissions") {
                LabeledContent("Calendar") {
                    if model.calendar.hasAccess {
                        Text("Allowed").foregroundStyle(.secondary)
                    } else if model.calendar.status == .notDetermined {
                        Button("Allow") { Task { await model.requestCalendarAccess() } }
                    } else {
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                        }
                    }
                }
                LabeledContent("Notifications") {
                    HStack {
                        Text(notificationStatus).foregroundStyle(.secondary)
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .font(Theme.body)
        .frame(width: 440)
        .task {
            switch await model.notifications.authorizationStatus() {
            case .authorized, .provisional: notificationStatus = "Allowed"
            case .denied: notificationStatus = "Off"
            default: notificationStatus = "Not asked yet"
            }
        }
    }
}
