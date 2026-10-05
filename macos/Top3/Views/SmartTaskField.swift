import SwiftUI

/// A task input that understands dates, "!" priority and "30m" estimates, and previews what it found.
/// Backspace right after a detected date (or the × in the preview) dismisses a wrong guess.
struct SmartTaskField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var detectDates: Bool
    var font: Font = Theme.Fonts.body
    var leadingIcon: IconName?
    var bordered = true
    var focusOnAppear = false
    var onSubmit: () -> Void = {}

    var body: some View {
        let parsed = TaskParser.parse(CaptureRouting.route(text).text, detectDates: detectDates)
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            InputField(placeholder: placeholder, text: $text, font: font, leadingIcon: leadingIcon, bordered: bordered,
                       focusOnAppear: focusOnAppear, onDeleteKey: {
                           guard parsed.dueDate != nil, parsed.dateAtEnd else { return false }
                           withAnimation(Theme.Motion.hover) { detectDates = false }
                           return true
                       }, onSubmit: onSubmit)
            ParsePreview(parsed: parsed) { withAnimation(Theme.Motion.hover) { detectDates = false } }
                .padding(.leading, leadingIcon == nil ? 0 : Theme.Size.icon + Theme.Space.s)
        }
        .onChange(of: text) { _, new in if new.isEmpty { detectDates = true } }
    }
}

/// One muted line: "Fri, Oct 9 3:00 PM · High · 30m". Hidden when nothing was parsed.
struct ParsePreview: View {
    let parsed: ParsedTask
    let onRemoveDate: () -> Void

    var body: some View {
        if parsed.hasExtras {
            HStack(spacing: Theme.Space.s) {
                if let due = parsed.dueDate {
                    HStack(spacing: Theme.Space.xs) {
                        Icon(.due, size: Theme.Size.dragHandle)
                        Text(due.formatted(parsed.hasDueTime
                            ? .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
                            : .dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        Button(action: onRemoveDate) { Icon(.close, size: Theme.Size.dragHandle) }
                            .buttonStyle(.plain)
                            .help("Not a date (Backspace)")
                    }
                }
                if let p = parsed.priority { Text("\(p.title) priority") }
                if let m = Fmt.minutes(parsed.estimateMinutes) { Text(m) }
                ForEach(parsed.tags, id: \.self) { Text("#\($0)") }
                Spacer(minLength: 0)
            }
            .font(Theme.Fonts.secondary)
            .foregroundStyle(Theme.Palette.textTertiary)
            .transition(.opacity)
        }
    }
}
