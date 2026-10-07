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

/// The app's colors and face, from the appearance it last wrote into the snapshot.
/// A forced mode (or a style with only one) fixes the colors to that variant; otherwise they follow the desktop.
private struct W {
    let text, secondary, tertiary, accent, accentForeground, background, border: Color
    private let family: StyleFont

    init(_ selection: AppearanceSelection?) {
        let s = selection ?? .default
        let mode = AppearanceRules.effectiveMode(s)
        func color(_ p: StylePair) -> Color {
            switch mode {
            case .system: Color(nsColor: ColorTokens.color(p))
            case .light: Color(nsColor: ColorTokens.color(p, fixed: .light))
            case .dark: Color(nsColor: ColorTokens.color(p, fixed: .dark))
            }
        }
        text = color(ColorTokens.pair(s.style, \.text))
        secondary = color(ColorTokens.pair(s.style, \.textSecondary))
        tertiary = color(ColorTokens.pair(s.style, \.textTertiary))
        background = color(ColorTokens.pair(s.style, \.background))
        border = color(ColorTokens.pair(s.style, \.border))
        accent = color(ColorTokens.accent(s))
        accentForeground = color(ColorTokens.accentForeground(s))
        family = AppearanceRules.font(s)
    }

    func font(_ size: CGFloat, _ medium: Bool = false) -> Font {
        switch family {
        case .inter: .custom(medium ? "Inter-Medium" : "Inter-Regular", fixedSize: size)
        case .serif: .system(size: size, weight: medium ? .medium : .regular, design: .serif)
        case .humanist: .custom(medium ? "Seravek-Medium" : "Seravek", fixedSize: size)
        }
    }
}

struct Top3WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Top3Entry
    private var w: W { W(entry.snapshot.appearance) }

    var body: some View {
        Group {
            if family == .systemSmall {
                Top3Column(snapshot: entry.snapshot, compact: true)
            } else if family == .systemLarge {
                VStack(alignment: .leading, spacing: 12) {
                    Top3Column(snapshot: entry.snapshot, compact: false, showFooter: false)
                        .fixedSize(horizontal: false, vertical: true)
                    Rectangle().fill(w.border).frame(height: 1)
                    ParkingColumn(snapshot: entry.snapshot, limit: 6)
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    Top3Column(snapshot: entry.snapshot, compact: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(w.border).frame(width: 1)
                    ParkingColumn(snapshot: entry.snapshot)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .containerBackground(w.background, for: .widget)
    }
}

private struct Top3Column: View {
    let snapshot: WidgetSnapshot
    private var w: W { W(snapshot.appearance) }
    let compact: Bool
    var showFooter = true

    var body: some View {
        let s = snapshot
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack {
                Text("TOP 3").font(w.font(10, true)).tracking(0.6).foregroundStyle(w.tertiary)
                Spacer()
                Text("\(s.doneCount)/3").font(w.font(10, true)).foregroundStyle(s.doneCount == 3 ? w.accent : w.tertiary)
            }
            ForEach(1...3, id: \.self) { slot in
                if let item = s.items.first(where: { $0.slot == slot }) {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().strokeBorder(item.done ? w.accent : w.tertiary, lineWidth: 1)
                            if item.done {
                                Circle().fill(w.accent)
                                Image("icon-done").resizable().renderingMode(.template).foregroundStyle(w.accentForeground).padding(2)
                            }
                        }
                        .frame(width: 12, height: 12)
                        Text(item.title)
                            .font(w.font(compact ? 11 : 12))
                            .foregroundStyle(item.done ? w.tertiary : w.text)
                            .strikethrough(item.done, color: w.tertiary)
                            .lineLimit(1)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text("\(slot)").font(w.font(10)).foregroundStyle(w.tertiary).frame(width: 12)
                        Text("Empty").font(w.font(11)).foregroundStyle(w.tertiary)
                    }
                }
            }
            if showFooter { Spacer(minLength: 0) }
            if !compact && showFooter {
                Text(s.items.isEmpty ? "Pick your Top 3 in ProTask" : "Updated \(s.updated.formatted(date: .omitted, time: .shortened))")
                    .font(w.font(10)).foregroundStyle(w.tertiary)
            }
        }
    }
}

/// Newest Parking Lot ideas, so they stay in view until they're sent to a list.
private struct ParkingColumn: View {
    let snapshot: WidgetSnapshot
    private var w: W { W(snapshot.appearance) }
    var limit = 3
    var compact = false

    var body: some View {
        let ideas = snapshot.ideas ?? []
        let count = snapshot.ideaCount ?? ideas.count
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack {
                Text("PARKING LOT").font(w.font(10, true)).tracking(0.6).foregroundStyle(w.tertiary)
                Spacer()
                Text("\(count)").font(w.font(10, true)).foregroundStyle(w.tertiary)
            }
            if ideas.isEmpty {
                Text("No ideas parked").font(w.font(11)).foregroundStyle(w.tertiary)
            } else {
                ForEach(Array(ideas.prefix(limit).enumerated()), id: \.offset) { _, title in
                    HStack(spacing: 6) {
                        Image("icon-idea").resizable().renderingMode(.template)
                            .foregroundStyle(w.tertiary).frame(width: 12, height: 12)
                        Text(title).font(w.font(compact ? 11 : 12)).foregroundStyle(w.secondary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            if count > limit {
                Text("+\(count - limit) more").font(w.font(10)).foregroundStyle(w.tertiary)
            }
        }
    }
}

/// Parking Lot on its own, for when you want ideas in view without the Top 3.
struct ParkingLotWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Top3Entry
    private var w: W { W(entry.snapshot.appearance) }

    var body: some View {
        ParkingColumn(snapshot: entry.snapshot, limit: 4, compact: family == .systemSmall)
            .containerBackground(w.background, for: .widget)
    }
}

struct Top3Widget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProTaskTop3", provider: Top3Provider()) { entry in
            Top3WidgetView(entry: entry)
        }
        .configurationDisplayName("Top 3")
        .description("Today's three, with what's done. Medium and large add your Parking Lot.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ParkingLotWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProTaskParkingLot", provider: Top3Provider()) { entry in
            ParkingLotWidgetView(entry: entry)
        }
        .configurationDisplayName("Parking Lot")
        .description("Your newest parked ideas.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ProTaskWidgets: WidgetBundle {
    var body: some Widget {
        Top3Widget()
        ParkingLotWidget()
    }
}
