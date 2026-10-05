import AppKit
import SwiftUI

/// The floating quick-add panel opened by the global hotkey. It takes typing without bringing ProTask forward.
@MainActor
final class QuickCaptureController: NSObject, NSWindowDelegate {
    static let shared = QuickCaptureController()
    private var panel: CapturePanel?

    func toggle() {
        if panel?.isVisible == true { close() } else { show() }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // A fresh view each time, so the field starts empty and focused.
        let root = QuickCaptureView(onClose: { [weak self] in self?.close() })
            .environment(AppModel.shared)
            .modelContainer(AppModel.shared.container)
        panel.contentView = NSHostingView(rootView: root)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            let size = NSSize(width: Theme.Size.capturePanelWidth, height: Theme.Size.capturePanelHeight)
            panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.minY + f.height * 0.68, width: size.width, height: size.height), display: true)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> CapturePanel {
        let p = CapturePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.delegate = self
        return p
    }

    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated { close() }
    }
}

final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct QuickCaptureView: View {
    @Environment(AppModel.self) private var model
    let onClose: () -> Void
    @State private var text = ""
    @State private var detectDates = true

    var body: some View {
        let route = CaptureRouting.route(text)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SmartTaskField(placeholder: "Add a task", text: $text, detectDates: $detectDates, font: Theme.Fonts.input,
                           leadingIcon: .add, bordered: false, focusOnAppear: true) {
                if model.capture(text, detectDates: detectDates) { onClose() }
            }
            HStack(spacing: Theme.Space.s) {
                Text("To \(route.list.title)")
                Spacer()
                Text("~ Nice to do   ? Parking Lot   esc to close")
            }
            .font(Theme.Fonts.secondary)
            .foregroundStyle(Theme.Palette.textTertiary)
            .padding(.leading, Theme.Size.icon + Theme.Space.s)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.border, lineWidth: Theme.Size.hairline))
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
        .onExitCommand(perform: onClose)
    }
}

/// Records a new global shortcut: click, then press the keys.
struct HotKeyRecorder: View {
    @State private var key = HotKey.saved
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Button(recording ? "Press keys…" : key.display) { recording ? stop() : start() }
                .buttonStyle(.ghost)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s)
                    .strokeBorder(recording ? Theme.Palette.accent : Theme.Palette.border, lineWidth: Theme.Size.hairline))
            if key != .default && !recording {
                Button("Reset") { set(.default) }.buttonStyle(.ghost)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        HotKeyService.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Esc cancels
            if let new = HotKey(event: event) { set(new) }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { HotKeyService.shared.register(HotKey.saved) }
        recording = false
    }

    private func set(_ new: HotKey) {
        new.save()
        key = new
        stop()
        if !HotKeyService.shared.register(new) {
            AppModel.shared.showToast("That shortcut is taken by another app.")
        }
    }
}
