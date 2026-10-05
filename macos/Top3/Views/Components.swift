import AppKit
import SwiftUI

// MARK: - Checkbox

/// 14pt circle with a thin border. Fills with the accent and draws a short check when completed.
struct Checkbox: View {
    let checked: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(checked ? Theme.Palette.accent : Theme.Palette.textTertiary, lineWidth: Theme.Size.hairline)
            Circle()
                .fill(Theme.Palette.accent)
                .opacity(checked ? 1 : 0)
            CheckShape()
                .trim(from: 0, to: checked ? 1 : 0)
                .stroke(Theme.Palette.accentForeground,
                        style: StrokeStyle(lineWidth: Theme.Size.checkStroke, lineCap: .round, lineJoin: .round))
                .padding(Theme.Size.checkInset)
        }
        .frame(width: Theme.Size.checkbox, height: Theme.Size.checkbox)
        .animation(Theme.Motion.standard, value: checked)
    }
}

private struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.42, y: r.minY + r.height * 0.82))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.9, y: r.minY + r.height * 0.22))
        return p
    }
}

// MARK: - Buttons

/// Small icon button with an optional tiny label. Ghost style: only a faint fill on hover.
struct IconButton: View {
    let icon: IconName
    let help: String
    var label: String?
    var active = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                Icon(icon)
                if let label { Text(label).font(Theme.Fonts.caption) }
            }
            .padding(.horizontal, label == nil ? 0 : Theme.Space.s)
            .frame(minWidth: Theme.Size.iconButton, minHeight: Theme.Size.iconButton)
            .foregroundStyle(active ? Theme.Palette.accent : hovering ? Theme.Palette.text : Theme.Palette.textSecondary)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(hovering ? Theme.Palette.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Text button with no border, faint fill on hover.
struct GhostButtonStyle: ButtonStyle {
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        GhostBody(configuration: configuration, destructive: destructive)
    }

    private struct GhostBody: View {
        let configuration: ButtonStyleConfiguration
        let destructive: Bool
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(Theme.Fonts.small)
                .foregroundStyle(hovering ? Theme.Palette.text : Theme.Palette.textSecondary)
                .padding(.horizontal, Theme.Space.s)
                .frame(minHeight: Theme.Size.iconButton)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.s)
                    .fill(configuration.isPressed ? Theme.Palette.selected : hovering ? Theme.Palette.hover : .clear))
                .contentShape(Rectangle())
                .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
        }
    }
}

/// The one filled button: inverted text color, used for the main action of a sheet.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.smallMedium)
            .foregroundStyle(Theme.Palette.background)
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: Theme.Size.iconButton)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.text))
            .opacity(!enabled ? Theme.Opacity.disabled : configuration.isPressed ? Theme.Opacity.pressed : 1)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == GhostButtonStyle {
    static var ghost: GhostButtonStyle { GhostButtonStyle() }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// "..." menu revealed on hover.
struct ActionsMenu<Content: View>: View {
    let help: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: content) {
            Icon(.more)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: Theme.Size.iconButton, height: Theme.Size.iconButton)
        .foregroundStyle(Theme.Palette.textSecondary)
        .help(help)
    }
}

// MARK: - Inputs

/// Hairline-bordered text field. No system focus ring; the border darkens on focus.
struct InputField: View {
    let placeholder: String
    @Binding var text: String
    var font: Font = Theme.Fonts.body
    var leadingIcon: IconName?
    var bordered = true
    var axis: Axis = .horizontal
    var focusOnAppear = false
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if let leadingIcon {
                Icon(leadingIcon)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.Palette.textTertiary), axis: axis)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(Theme.Palette.text)
                .focused($focused)
                .focusEffectDisabled()
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, bordered ? Theme.Space.s : 0)
        .padding(.vertical, bordered ? Theme.Space.s - Theme.Space.xxs : 0)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m)
            .strokeBorder(bordered ? (focused ? Theme.Palette.textTertiary : Theme.Palette.border) : .clear,
                          lineWidth: Theme.Size.hairline))
        .animation(Theme.Motion.hover, value: focused)
        .onAppear { if focusOnAppear { DispatchQueue.main.async { focused = true } } }
    }
}

// MARK: - Structure

struct Hairline: View {
    var vertical = false
    var body: some View {
        Rectangle()
            .fill(Theme.Palette.border)
            .frame(width: vertical ? Theme.Size.hairline : nil, height: vertical ? nil : Theme.Size.hairline)
    }
}

/// Tiny uppercase grey label with an optional count.
struct SectionLabel: View {
    let title: String
    var detail: String?
    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Text(title.uppercased())
                .font(Theme.Fonts.label)
                .tracking(Theme.labelTracking)
                .foregroundStyle(Theme.Palette.textTertiary)
            if let detail {
                Text(detail).font(Theme.Fonts.caption).foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }
}

/// Empty state: one muted line.
struct EmptyLine: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.Fonts.small)
            .foregroundStyle(Theme.Palette.textTertiary)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.row, alignment: .leading)
    }
}

struct InsertionLine: View {
    let visible: Bool
    var body: some View {
        Rectangle()
            .fill(Theme.Palette.accent)
            .frame(height: Theme.Size.hairline)
            .opacity(visible ? 1 : 0)
    }
}

struct ToastView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.Fonts.small)
            .foregroundStyle(Theme.Palette.text)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.elevated))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.border, lineWidth: Theme.Size.hairline))
            .shadow(color: Theme.Palette.shadow, radius: Theme.Size.hairline, y: Theme.Size.hairline)
    }
}

struct DragPreview: View {
    let title: String
    var body: some View {
        Text(title)
            .font(Theme.Fonts.body)
            .foregroundStyle(Theme.Palette.text)
            .lineLimit(1)
            .padding(.horizontal, Theme.Space.m)
            .frame(height: Theme.Size.row)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.elevated))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.border, lineWidth: Theme.Size.hairline))
    }
}

extension View {
    /// Faint fill while hovered (or a stronger one while selected).
    func rowFill(hovering: Bool, selected: Bool = false) -> some View {
        background(RoundedRectangle(cornerRadius: Theme.Radius.s)
            .fill(selected ? Theme.Palette.selected : hovering ? Theme.Palette.hover : .clear))
    }
}

// MARK: - Window

/// Flat, title-less window: transparent title bar, app background color, no separator.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ConfiguringView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ConfiguringView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.titlebarSeparatorStyle = .none
            w.styleMask.insert(.fullSizeContentView)
            w.backgroundColor = Theme.Palette.nsBackground
        }
    }
}

/// Lets an empty area (header, sidebar top) drag the window, and double-click to zoom.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
        }
    }
}
