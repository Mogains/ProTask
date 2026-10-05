import SwiftUI

/// Compact running timer for the sidebar footer (and the header when the sidebar is hidden).
struct FocusTimerView: View {
    @Environment(AppModel.self) private var model
    var compact = false

    var body: some View {
        if let f = model.focus {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = f.remaining(at: context.date)
                HStack(spacing: Theme.Space.s) {
                    Icon(.later).foregroundStyle(Theme.Palette.accent)
                    if !compact {
                        Text(f.title).font(Theme.Fonts.small).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                        Spacer(minLength: Theme.Space.xs)
                    }
                    Text(String(format: "%d:%02d", left / 60, left % 60))
                        .font(Theme.Fonts.mono)
                        .foregroundStyle(Theme.Palette.text)
                    IconButton(icon: .close, help: "Stop and log the time") { model.stopFocus() }
                }
            }
            .padding(.leading, compact ? 0 : Theme.Space.s)
            .frame(height: Theme.Size.sidebarRow)
            .help("Focus on \(f.title)")
        }
    }
}

/// Small sheet asking for a custom focus length.
struct CustomFocusSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: CustomFocusRequest
    @State private var minutes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InputField(placeholder: "Minutes", text: $minutes, font: Theme.Fonts.input, leadingIcon: .later, bordered: false,
                       focusOnAppear: true, onSubmit: start)
                .padding(Theme.Space.l)
            Hairline()
            HStack {
                Text("Focus on \(model.task(request.taskID)?.title ?? "anything")")
                    .font(Theme.Fonts.secondary).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.ghost).keyboardShortcut(.cancelAction)
                Button("Start") { start() }.buttonStyle(.primary).disabled(Int(minutes) == nil)
            }
            .padding(Theme.Space.m)
        }
        .frame(width: Theme.Size.quickAddWidth)
    }

    private func start() {
        guard let m = Int(minutes.trimmingCharacters(in: .whitespaces)), m > 0 else { return }
        model.startFocus(on: model.task(request.taskID), minutes: m)
        dismiss()
    }
}
