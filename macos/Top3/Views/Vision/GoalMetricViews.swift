import Charts
import SwiftData
import SwiftUI

// MARK: - Metric section

/// The goal's number: name and unit, start, current and target, and a small graph of the logged values.
struct GoalMetricSection: View {
    @Environment(AppModel.self) private var model
    let goal: Goal
    let color: TimelineColor

    @Query private var logs: [GoalLog]
    @State private var adding = false

    init(goal: Goal, color: TimelineColor) {
        self.goal = goal
        self.color = color
        let id = goal.id
        _logs = Query(filter: #Predicate<GoalLog> { $0.goalID == id })
    }

    private var hasFields: Bool {
        goal.metricStart != nil || goal.metricCurrent != nil || goal.metricTarget != nil || !goal.metricName.isEmpty
    }

    var body: some View {
        PanelSection(title: "Metric", detail: goal.metric.map { "\($0.percent)%" }) {
            if hasFields || adding {
                Button("Remove") {
                    adding = false
                    model.setMetricFields(goal.id, name: "", start: nil, current: nil, target: nil, unit: "")
                }
                .buttonStyle(.ghost)
                .help("Remove the metric (logged values stay in the updates)")
            }
        } content: {
            if hasFields || adding {
                fields
                    .padding(.bottom, Theme.Space.s)
                if let metric = goal.metric {
                    let points = MetricSeries.points(metric: metric, startDate: goal.startDate, createdAt: goal.createdAt,
                                                     logs: logs.map(\.entry), today: Date())
                    GoalMetricChart(points: points, target: metric.target, unit: metric.unit, name: metric.name, color: color,
                                    summary: summary(metric))
                } else {
                    Text("Fill in start, current and target to see the graph.")
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            } else {
                HStack(spacing: Theme.Space.s) {
                    Text("Track a number, like a long run or a balance.")
                        .font(Theme.Fonts.small)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Add metric") { adding = true }.buttonStyle(.ghost)
                }
            }
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                CommitField(placeholder: "Name, like Long run", value: goal.metricName) { name in save(name: name) }
                CommitField(placeholder: "Unit", value: goal.metricUnit) { unit in save(unit: unit) }
                    .frame(width: Theme.GoalPanel.unitField)
            }
            HStack(alignment: .top, spacing: Theme.Space.s) {
                numberField("Start", goal.metricStart) { save(start: .some($0)) }
                numberField("Current", goal.metricCurrent) { save(current: .some($0)) }
                numberField("Target", goal.metricTarget) { save(target: .some($0)) }
            }
        }
    }

    private func numberField(_ label: String, _ value: Double?, set: @escaping (Double?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .accessibilityHidden(true)
            CommitField(placeholder: label, value: MetricInput.text(value), alignment: .trailing,
                        isValid: { $0.trimmingCharacters(in: .whitespaces).isEmpty || MetricInput.number($0) != nil }) { text in
                set(MetricInput.number(text))
            }
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    /// Writes the fields, changing only the one given.
    private func save(name: String? = nil, unit: String? = nil, start: Double?? = nil, current: Double?? = nil, target: Double?? = nil) {
        model.setMetricFields(goal.id, name: name ?? goal.metricName,
                              start: start ?? goal.metricStart, current: current ?? goal.metricCurrent,
                              target: target ?? goal.metricTarget, unit: unit ?? goal.metricUnit)
    }

    private func summary(_ m: GoalMetric) -> String {
        let now = MetricInput.format(m.current, unit: m.unit)
        let goalValue = MetricInput.format(m.target, unit: m.unit)
        if m.isReached { return "\(now), target of \(goalValue) reached" }
        return "\(now) now · \(MetricInput.format(m.remaining, unit: m.unit)) to go to \(goalValue)"
    }
}

extension GoalLog {
    var entry: GoalLogEntry {
        GoalLogEntry(id: id, date: date, createdAt: createdAt, text: text, metricValue: metricValue, progress: progress)
    }
}

// MARK: - Graph

/// A small line graph of a metric: hairline grid, the timeline's hue, a soft tonal area, and the target as a line.
/// Hover to read a value.
struct GoalMetricChart: View {
    let points: [MetricPoint]
    let target: Double
    let unit: String
    let name: String
    let color: TimelineColor
    /// The line under the graph; while hovering it reads out the point instead.
    let summary: String

    @State private var hovered: MetricPoint?

    var body: some View {
        let hue = Theme.Vision.color(color)
        let domain = MetricSeries.valueDomain(points, target: target)
        let shown = hovered ?? points.last
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Chart {
                ForEach(points) { p in
                    AreaMark(x: .value("Day", p.date), yStart: .value("Base", domain.lowerBound), yEnd: .value("Value", p.value))
                        .foregroundStyle(LinearGradient(colors: [hue.opacity(Theme.Vision.Alpha.areaTop), hue.opacity(Theme.Vision.Alpha.areaBottom)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", p.date), y: .value("Value", p.value))
                        .foregroundStyle(hue)
                        .lineStyle(StrokeStyle(lineWidth: Theme.GoalPanel.chartLine, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                RuleMark(y: .value("Target", target))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: Theme.Size.hairline))
                    .annotation(position: .top, alignment: .leading, spacing: Theme.Space.xxs) {
                        Text("Target \(MetricInput.format(target, unit: unit))")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                if let hovered {
                    RuleMark(x: .value("Day", hovered.date))
                        .foregroundStyle(Theme.Palette.textTertiary.opacity(Theme.Vision.Alpha.chartGuide))
                        .lineStyle(StrokeStyle(lineWidth: Theme.Size.hairline))
                }
                if let shown {
                    PointMark(x: .value("Day", shown.date), y: .value("Value", shown.value))
                        .symbol { dot(hue) }
                }
            }
            .chartYScale(domain: domain)
            .chartXScale(domain: xDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: xFormat)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: Theme.Size.hairline))
                        .foregroundStyle(Theme.Palette.border)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(MetricInput.format(v)).font(Theme.Fonts.caption).foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case let .active(location):
                                guard let plot = proxy.plotFrame else { return }
                                let x = location.x - geo[plot].origin.x
                                guard let date: Date = proxy.value(atX: x) else { return }
                                hovered = points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
                            case .ended:
                                hovered = nil
                            }
                        }
                }
            }
            .frame(height: Theme.GoalPanel.chartHeight)
            .accessibilityElement()
            .accessibilityLabel(name.isEmpty ? "Metric graph" : "\(name) graph")
            .accessibilityValue(accessibilitySummary)

            Group {
                if let hovered {
                    HStack(spacing: Theme.Space.xs) {
                        Text(VisionFormat.day(hovered.date))
                        Text(MetricInput.format(hovered.value, unit: unit)).foregroundStyle(Theme.Palette.text)
                        Text(kindLabel(hovered.kind))
                    }
                    .foregroundStyle(Theme.Palette.textTertiary)
                } else {
                    Text(summary).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .font(Theme.Fonts.secondary)
            .monospacedDigit()
            .accessibilityHidden(hovered != nil)
        }
    }

    private func dot(_ hue: Color) -> some View {
        Circle()
            .fill(hue)
            .frame(width: Theme.GoalPanel.chartDot, height: Theme.GoalPanel.chartDot)
            .padding(Theme.GoalPanel.chartRing)
            .background(Circle().fill(Theme.Palette.surface))
    }

    /// The first point to today (or the last point, if later), so a single point still has room.
    private var xDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let first = points.first?.date ?? cal.startOfDay(for: Date())
        let last = max(points.last?.date ?? first, cal.startOfDay(for: Date()))
        let end = last > first ? last : (cal.date(byAdding: .day, value: 1, to: first) ?? first)
        return first...end
    }

    private var xFormat: Date.FormatStyle {
        let years = Calendar.current.dateComponents([.month], from: xDomain.lowerBound, to: xDomain.upperBound).month ?? 0
        return years >= 12 ? .dateTime.month(.abbreviated).year(.twoDigits) : .dateTime.month(.abbreviated).day()
    }

    private func kindLabel(_ kind: MetricPoint.Kind) -> String {
        switch kind {
        case .start: "start"
        case .logged: "logged"
        case .current: "now"
        }
    }

    private var accessibilitySummary: String {
        guard let first = points.first, let last = points.last else { return "No values yet" }
        return "From \(MetricInput.format(first.value, unit: unit)) on \(VisionFormat.day(first.date)) to "
            + "\(MetricInput.format(last.value, unit: unit)) on \(VisionFormat.day(last.date)). Target \(MetricInput.format(target, unit: unit))."
    }
}
