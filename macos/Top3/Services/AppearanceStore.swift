import AppKit
import Observation
import SwiftUI

/// The appearance the user picked: mode, style, accent and font. Theme reads `palette` from here, so a change
/// redraws every view that uses a color, font or radius, and AppKit follows through NSApp.appearance.
/// Saved in UserDefaults. Throwaway runs (TOP3_STORE_PATH) never save; they read TOP3_APPEARANCE, TOP3_STYLE,
/// TOP3_ACCENT and TOP3_FONT instead, so screenshots can show any combination.
@Observable
final class AppearanceStore {
    static let shared = AppearanceStore()

    /// Shared with the light and dark toggle that came before styles, so a saved mode carries over.
    static let modeKey = "appearance"
    static let styleKey = "appearanceStyle"
    static let accentKey = "appearanceAccent"
    static let fontKey = "appearanceFont"

    private(set) var selection: AppearanceSelection
    private(set) var palette: ThemePalette

    /// Runs after each change (the widget's snapshot carries the appearance).
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults?
    /// Windows whose background color follows the style.
    @ObservationIgnored private let windows = NSHashTable<NSWindow>.weakObjects()

    private init() {
        let env = ProcessInfo.processInfo.environment
        let throwaway = env["TOP3_STORE_PATH"] != nil
        let d: UserDefaults? = throwaway ? nil : .standard
        func read(_ key: String, _ envName: String) -> String? { d?.string(forKey: key) ?? (throwaway ? env[envName] : nil) }
        var s = AppearanceSelection()
        s.mode = read(Self.modeKey, "TOP3_APPEARANCE").flatMap(AppearanceMode.init) ?? .system
        s.style = read(Self.styleKey, "TOP3_STYLE").flatMap(AppearanceStyle.init) ?? .graphite
        s.accent = read(Self.accentKey, "TOP3_ACCENT").flatMap(AccentChoice.init)
        s.font = read(Self.fontKey, "TOP3_FONT").flatMap(StyleFont.init)
        defaults = d
        selection = s
        palette = ThemePalette(s)
    }

    /// The mode in effect: the chosen one, unless the style only has one.
    var effectiveMode: AppearanceMode { AppearanceRules.effectiveMode(selection) }

    func setMode(_ mode: AppearanceMode) { update { $0.mode = mode } }
    func setStyle(_ style: AppearanceStyle) { update { $0.style = style } }
    /// Nil goes back to the style's own accent.
    func setAccent(_ accent: AccentChoice?) { update { $0.accent = accent } }
    func setFont(_ font: StyleFont) { update { $0.font = font } }

    /// Swaps light and dark, for the command palette. False when the style has only one mode.
    @discardableResult
    func toggleMode() -> Bool {
        guard AppearanceRules.modes(for: selection.style).count > 1 else { return false }
        let isDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        setMode(isDark ? .light : .dark)
        return true
    }

    /// Sets the app's appearance for the mode and the style's window background. Call once at launch,
    /// before any window shows, so the first frame is already right.
    func applyToAppKit() {
        switch effectiveMode {
        case .system: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
        for w in windows.allObjects { w.backgroundColor = palette.nsBackground }
    }

    /// A window whose background should follow the style (see WindowConfigurator).
    func register(_ window: NSWindow) {
        windows.add(window)
        window.backgroundColor = palette.nsBackground
    }

    private func update(_ change: (inout AppearanceSelection) -> Void) {
        let old = selection
        var next = old
        change(&next)
        guard next != old else { return }
        let newPalette = next.style != old.style || AppearanceRules.accent(next) != AppearanceRules.accent(old)
            || AppearanceRules.font(next) != AppearanceRules.font(old)
        let newMode = AppearanceRules.effectiveMode(next) != AppearanceRules.effectiveMode(old)
        let apply = {
            self.selection = next
            if newPalette { self.palette = ThemePalette(next) }
            self.save()
            self.applyToAppKit()
        }
        if newPalette || newMode { AppearanceFade.run(apply) } else { apply() }
        onChange?()
    }

    private func save() {
        guard let d = defaults else { return }
        d.set(selection.mode.rawValue, forKey: Self.modeKey)
        d.set(selection.style.rawValue, forKey: Self.styleKey)
        if let a = selection.accent { d.set(a.rawValue, forKey: Self.accentKey) } else { d.removeObject(forKey: Self.accentKey) }
        if let f = selection.font { d.set(f.rawValue, forKey: Self.fontKey) } else { d.removeObject(forKey: Self.fontKey) }
    }
}

// MARK: - Cross-fade

/// Cross-fades every visible window from how it looks now to how it looks after a change. A still picture of each
/// window sits on top in a borderless child window while the real one redraws underneath, then fades out.
/// Nothing half-updated is ever on screen, so there is no flash. A fade is a dissolve, not motion, so it stays
/// with Reduce Motion on.
enum AppearanceFade {
    private static let coverID = NSUserInterfaceItemIdentifier("ProTaskAppearanceFade")

    static func run(_ change: () -> Void) {
        let covers = NSApplication.shared.windows.compactMap(Cover.init)
        change()
        guard !covers.isEmpty else { return }
        // One turn of the run loop lets SwiftUI and AppKit redraw underneath before the picture starts to fade.
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Theme.Motion.appearanceFade
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for c in covers { c.panel.animator().alphaValue = 0 }
            } completionHandler: {
                for c in covers { c.remove() }
            }
        }
    }

    private struct Cover {
        let panel: NSPanel
        weak var parent: NSWindow?

        init?(_ window: NSWindow) {
            guard window.identifier != AppearanceFade.coverID, window.isVisible, !window.isMiniaturized, window.alphaValue > 0,
                  !String(describing: type(of: window)).contains("StatusBar"),
                  let frameView = window.contentView?.superview ?? window.contentView,
                  let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return nil }
            frameView.cacheDisplay(in: frameView.bounds, to: rep)
            let image = NSImage(size: frameView.bounds.size)
            image.addRepresentation(rep)

            let panel = NSPanel(contentRect: window.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.identifier = AppearanceFade.coverID
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            let view = NSImageView(image: image)
            view.imageScaling = .scaleAxesIndependently
            view.wantsLayer = true
            // The picture is square-cornered; round it like the window under it.
            view.layer?.cornerRadius = Theme.Size.windowCorner
            view.layer?.masksToBounds = true
            panel.contentView = view
            window.addChildWindow(panel, ordered: .above)
            self.panel = panel
            parent = window
        }

        func remove() {
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }
}
