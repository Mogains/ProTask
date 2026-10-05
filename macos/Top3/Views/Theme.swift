import SwiftUI
import UniformTypeIdentifiers

/// Small type, tight spacing, greys only. The one accent is a muted slate defined in the asset catalog.
enum Theme {
    static let body = Font.system(size: 13)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
    static let secondary = Font.system(size: 11)
    static let caption = Font.system(size: 10, weight: .medium)
    static let sectionHeader = Font.system(size: 11, weight: .semibold)
    static let title = Font.system(size: 18, weight: .semibold)

    static let rowHover = Color.primary.opacity(0.04)
    static let rowSelected = Color.primary.opacity(0.09)
    static let hairline = Color.primary.opacity(0.09)
    static let content = Color(nsColor: .textBackgroundColor)
}

extension UTType {
    static let top3Task = UTType(exportedAs: "com.anmolbhatt.top3.task")
}

/// What gets dragged around: just the task's id.
struct TaskRef: Codable, Transferable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .top3Task)
    }
}

struct SectionHeader: View {
    let title: String
    var detail: String?
    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased()).font(Theme.sectionHeader).foregroundStyle(.secondary).tracking(0.4)
            if let detail { Text(detail).font(Theme.secondary).foregroundStyle(.tertiary) }
        }
    }
}

struct DragPreview: View {
    let title: String
    var body: some View {
        Text(title)
            .font(Theme.body)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline))
    }
}

enum Fmt {
    static func due(_ t: TaskItem, today: String) -> (text: String, overdue: Bool)? {
        guard let due = t.dueDate else { return nil }
        let key = DayKey.dateKey(due)
        let day: String
        if key == today { day = "Today" }
        else if key == DayKey.adding(1, to: today) { day = "Tomorrow" }
        else if key == DayKey.adding(-1, to: today) { day = "Yesterday" }
        else { day = due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
        let text = t.hasDueTime ? "\(day) \(due.formatted(date: .omitted, time: .shortened))" : day
        return (text, key < today)
    }

    static func minutes(_ m: Int?) -> String? {
        guard let m, m > 0 else { return nil }
        if m < 60 { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }

    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
}
