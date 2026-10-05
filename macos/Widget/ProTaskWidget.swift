import SwiftUI
import WidgetKit

/// Desktop widget: today's Top 3 with completion state, in the app's greys.
struct Top3Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct Top3Provider: TimelineProvider {
    func placeholder(in context: Context) -> Top3Entry { Top3Entry(date: Date(), snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (Top3Entry) -> Void) {
        completion(Top3Entry(date: Date(), snapshot: context.isPreview ? .placeholder : (WidgetSnapshot.read() ?? .placeholder)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Top3Entry>) -> Void) {
        let entry = Top3Entry(date: Date(), snapshot: WidgetSnapshot.read() ?? WidgetSnapshot(updated: Date(), day: "", items: []))
        // The app asks for a reload on every change; this is only a fallback.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

private enum W {
    static let text = Color(nsColor: ColorTokens.color(ColorTokens.text))
    static let secondary = Color(nsColor: ColorTokens.color(ColorTokens.textSecondary))
    static let tertiary = Color(nsColor: ColorTokens.color(ColorTokens.textTertiary))
    static let accent = Color(nsColor: ColorTokens.color(ColorTokens.accent))
    static let accentForeground = Color(nsColor: ColorTokens.color(ColorTokens.accentForeground))
    static let background = Color(nsColor: ColorTokens.color(ColorTokens.background))
    static let border = Color(nsColor: ColorTokens.color(ColorTokens.border))
    static func font(_ size: CGFloat, _ medium: Bool = false) -> Font { .custom(medium ? "Inter-Medium" : "Inter-Regular", fixedSize: size) }
}

struct Top3WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Top3Entry

    var body: some View {
        Group {
            if family == .systemSmall {
                Top3Column(snapshot: entry.snapshot, compact: true)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    Top3Column(snapshot: entry.snapshot, compact: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(W.border).frame(width: 1)
                    ParkingColumn(snapshot: entry.snapshot)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .containerBackground(W.background, for: .widget)
    }
}

private struct Top3Column: View {
    let snapshot: WidgetSnapshot
    let compact: Bool

    var body: some View {
        let s = snapshot
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack {
                Text("TOP 3").font(W.font(10, true)).tracking(0.6).foregroundStyle(W.tertiary)
                Spacer()
                Text("\(s.doneCount)/3").font(W.font(10, true)).foregroundStyle(s.doneCount == 3 ? W.accent : W.tertiary)
            }
            ForEach(1...3, id: \.self) { slot in
                if let item = s.items.first(where: { $0.slot == slot }) {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().strokeBorder(item.done ? W.accent : W.tertiary, lineWidth: 1)
                            if item.done {
                                Circle().fill(W.accent)
                                Image("icon-done").resizable().renderingMode(.template).foregroundStyle(W.accentForeground).padding(2)
                            }
                        }
                        .frame(width: 12, height: 12)
                        Text(item.title)
                            .font(W.font(compact ? 11 : 12))
                            .foregroundStyle(item.done ? W.tertiary : W.text)
                            .strikethrough(item.done, color: W.tertiary)
                            .lineLimit(1)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text("\(slot)").font(W.font(10)).foregroundStyle(W.tertiary).frame(width: 12)
                        Text("Empty").font(W.font(11)).foregroundStyle(W.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            if !compact {
                Text(s.items.isEmpty ? "Pick your Top 3 in ProTask" : "Updated \(s.updated.formatted(date: .omitted, time: .shortened))")
                    .font(W.font(10)).foregroundStyle(W.tertiary)
            }
        }
    }
}

/// Newest Parking Lot ideas, so they stay in view until they're sent to a list.
private struct ParkingColumn: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let ideas = snapshot.ideas ?? []
        let count = snapshot.ideaCount ?? ideas.count
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PARKING LOT").font(W.font(10, true)).tracking(0.6).foregroundStyle(W.tertiary)
                Spacer()
                Text("\(count)").font(W.font(10, true)).foregroundStyle(W.tertiary)
            }
            if ideas.isEmpty {
                Text("No ideas parked").font(W.font(11)).foregroundStyle(W.tertiary)
            } else {
                ForEach(Array(ideas.prefix(3).enumerated()), id: \.offset) { _, title in
                    HStack(spacing: 6) {
                        Image("icon-idea").resizable().renderingMode(.template)
                            .foregroundStyle(W.tertiary).frame(width: 12, height: 12)
                        Text(title).font(W.font(12)).foregroundStyle(W.secondary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            if count > 3 {
                Text("+\(count - 3) more").font(W.font(10)).foregroundStyle(W.tertiary)
            }
        }
    }
}

@main
struct ProTaskWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProTaskTop3", provider: Top3Provider()) { entry in
            Top3WidgetView(entry: entry)
        }
        .configurationDisplayName("Top 3")
        .description("Today's three, with what's done. Medium adds your Parking Lot.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
