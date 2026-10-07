import AppKit
import SwiftUI

/// Settings > Appearance: mode, style (with a live preview of each), accent and, for styles that offer one, the font.
/// Every change cross-fades the whole app and is saved at once.
struct AppearanceSettings: View {
    private var store: AppearanceStore { .shared }

    var body: some View {
        let selection = store.selection
        let style = selection.style
        VStack(alignment: .leading, spacing: 0) {
            row("Mode") {
                let modes = AppearanceRules.modes(for: style)
                if modes.count > 1 {
                    Segments(options: modes, selection: Binding(get: { store.effectiveMode }, set: { store.setMode($0) })) { $0.title }
                } else {
                    Text(modes[0].title).foregroundStyle(Theme.Palette.text)
                    Text("\(style.title) comes in \(modes[0].title.lowercased()) only").foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            SectionLabel(title: "Style").padding(.horizontal, Theme.Space.l).frame(height: Theme.Size.row)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s, alignment: .top),
                                     count: Theme.AppearancePicker.columns),
                      alignment: .leading, spacing: Theme.Space.m) {
                ForEach(AppearanceStyle.allCases, id: \.self) { s in
                    StyleCard(style: s, selection: selection, chosen: s == style) { store.setStyle(s) }
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.s)
            row("Accent") {
                if AppearanceRules.hasAccent(style) {
                    AccentSwatches(selection: selection) { store.setAccent($0) }
                    if selection.accent != nil {
                        Button("Reset") { store.setAccent(nil) }
                            .buttonStyle(.ghost)
                            .help("Go back to \(style.title)'s own accent, \(style.spec.defaultAccent?.title ?? "")")
                    }
                } else {
                    Text("\(style.title) has no accent").foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            if style.spec.fonts.count > 1 {
                row("Font") {
                    Segments(options: style.spec.fonts, selection: Binding(get: { AppearanceRules.font(selection) },
                                                                          set: { store.setFont($0) })) { $0.title }
                }
            }
            Text("Every combination keeps text and accents readable.")
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.Palette.textTertiary)
                .padding(.horizontal, Theme.Space.l)
                .padding(.top, Theme.Space.xs)
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Theme.Space.s) {
            Text(label)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: Theme.Size.propertyLabel + Theme.Space.xl, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.l)
        .frame(height: Theme.Size.row)
    }
}

// MARK: - Style card

/// One style as a small mock window drawn with that style's own tokens, in the mode it would show in,
/// with the chosen accent. Click (or Space with keyboard navigation) to switch.
private struct StyleCard: View {
    let style: AppearanceStyle
    let selection: AppearanceSelection
    let chosen: Bool
    let choose: () -> Void
    @State private var hovering = false

    var body: some View {
        var preview = selection
        preview.style = style
        let palette = ThemePalette(preview)
        let radius = palette.radiusMedium
        return Button(action: choose) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                MockWindow(palette: palette)
                    .frame(height: Theme.AppearancePicker.previewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: radius))
                    .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(palette.border, lineWidth: palette.hairline))
                    .environment(\.colorScheme, Self.scheme(for: preview))
                    .padding(Theme.AppearancePicker.selectionStroke + Theme.Space.xxs)
                    .overlay(RoundedRectangle(cornerRadius: radius + Theme.Space.xxs + Theme.AppearancePicker.selectionStroke)
                        .strokeBorder(chosen ? Theme.Palette.accent : hovering ? Theme.Palette.border : .clear,
                                      lineWidth: Theme.AppearancePicker.selectionStroke))
                VStack(alignment: .leading, spacing: 0) {
                    Text(style.title).font(Theme.Fonts.smallMedium).foregroundStyle(Theme.Palette.text)
                    Text(style.blurb)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Space.xxs)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
        .accessibilityLabel("\(style.title) style, \(style.blurb)")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// The scheme the style would show in: its only one, the chosen mode, or the system's.
    static func scheme(for s: AppearanceSelection) -> ColorScheme {
        switch AppearanceRules.effectiveMode(s) {
        case .light: return .light
        case .dark: return .dark
        case .system: return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : .light
        }
    }
}

/// A sidebar with a selected row, a title, and two tasks (one done) in the style's face.
private struct MockWindow: View {
    let palette: ThemePalette
    private typealias P = Theme.AppearancePicker

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.xs + Theme.Space.xxs) {
                line(palette.textTertiary, P.lineLengths[1])
                HStack(spacing: Theme.Space.xxs) {
                    Rectangle().fill(palette.accent).frame(width: Theme.Size.indicator, height: P.line * 2)
                    line(palette.text, P.lineLengths[0])
                }
                .padding(.vertical, Theme.Space.xxs)
                .background(palette.selected)
                line(palette.textSecondary, P.lineLengths[2])
                line(palette.textSecondary, P.lineLengths[1])
            }
            .padding(Theme.Space.xs + Theme.Space.xxs)
            .frame(width: P.previewSidebar, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(palette.surface)
            Rectangle().fill(palette.border).frame(width: palette.hairline)
            VStack(alignment: .leading, spacing: Theme.Space.xs + Theme.Space.xxs) {
                Text("Aa")
                    .font(Theme.font(P.sampleText, .semibold, family: palette.font))
                    .foregroundStyle(palette.text)
                task(done: true, P.lineLengths[1])
                task(done: false, P.lineLengths[0])
            }
            .padding(Theme.Space.s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.background)
        }
    }

    private func line(_ color: Color, _ length: CGFloat) -> some View {
        GeometryReader { geo in
            Capsule().fill(color).frame(width: geo.size.width * length, height: P.line)
        }
        .frame(height: P.line)
    }

    private func task(done: Bool, _ length: CGFloat) -> some View {
        HStack(spacing: Theme.Space.xs) {
            ZStack {
                Circle().strokeBorder(done ? palette.accent : palette.textTertiary, lineWidth: palette.hairline)
                if done {
                    Circle().fill(palette.accent)
                    CheckShape()
                        .stroke(palette.accentForeground, style: StrokeStyle(lineWidth: P.previewCheckStroke, lineCap: .round, lineJoin: .round))
                        .padding(P.previewCheckInset)
                }
            }
            .frame(width: P.previewCheckbox, height: P.previewCheckbox)
            line(done ? palette.textTertiary : palette.text, length)
        }
    }
}

// MARK: - Accent swatches

/// The accent options as small circles in their tone for the current mode; a ring marks the one in use.
private struct AccentSwatches: View {
    let selection: AppearanceSelection
    let choose: (AccentChoice) -> Void

    var body: some View {
        let current = AppearanceRules.accent(selection)
        HStack(spacing: Theme.Space.xs) {
            ForEach(AccentChoice.allCases, id: \.self) { accent in
                let on = accent == current
                Button { choose(accent) } label: {
                    Circle()
                        .fill(Color(nsColor: ColorTokens.color(accent.tones)))
                        .frame(width: Theme.AppearancePicker.swatch, height: Theme.AppearancePicker.swatch)
                        .padding(Theme.AppearancePicker.swatchGap)
                        .overlay(Circle().strokeBorder(on ? Theme.Palette.text : .clear, lineWidth: Theme.AppearancePicker.swatchRing))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(accent == selection.style.spec.defaultAccent ? "\(accent.title), \(selection.style.title)'s own" : accent.title)
                .accessibilityLabel("\(accent.title) accent")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
