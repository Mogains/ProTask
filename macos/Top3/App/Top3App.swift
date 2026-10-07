import SwiftData
import SwiftUI

@main
struct ProTaskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showMenuBarExtra") private var showMenuBar = true
    private let model: AppModel

    init() {
        Theme.registerFonts()
        // Before any window exists, so the first frame already has the saved mode and style.
        AppearanceStore.shared.applyToAppKit()
        model = AppModel.shared
    }

    var body: some Scene {
        Window("ProTask", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: Theme.Size.windowMinWidth, minHeight: Theme.Size.windowMinHeight)
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(model.container)
        .defaultSize(width: 1180, height: 740)
        .commands { Top3Commands(model: model) }

        Window("AI Chat", id: "chat") {
            ChatWindowContent()
                .environment(model)
                .frame(minWidth: Theme.Size.chatWindowMinWidth, minHeight: Theme.Size.chatWindowMinHeight)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 520, height: 720)

        Settings {
            SettingsView()
                .environment(model)
                .modelContainer(model.container)
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarQuickAdd()
                .environment(model)
                .modelContainer(model.container)
        } label: {
            MenuBarLabel(model: model)
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
