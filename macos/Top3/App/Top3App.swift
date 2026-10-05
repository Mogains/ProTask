import SwiftData
import SwiftUI

@main
struct Top3App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showMenuBarExtra") private var showMenuBar = true
    private let model = AppModel.shared

    var body: some Scene {
        Window("Top 3", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 460)
        }
        .modelContainer(model.container)
        .defaultSize(width: 1120, height: 720)
        .commands { Top3Commands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
                .modelContainer(model.container)
        }

        MenuBarExtra("Top 3", systemImage: "checklist", isInserted: $showMenuBar) {
            MenuBarQuickAdd()
                .environment(model)
                .modelContainer(model.container)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // The notification delegate must be set before launch finishes so that
        // actions chosen while the app was closed are delivered.
        MainActor.assumeIsolated { AppModel.shared.notifications.configure() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in await AppModel.shared.onLaunch() }
    }

    /// Keep running for the menu bar item and reminders when the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
