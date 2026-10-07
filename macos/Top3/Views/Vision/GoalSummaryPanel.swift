import SwiftUI

/// The selected goal at a glance, beside the board: its timeline, status, dates, progress and notes.
/// The full goal editor (metric graph, images, links, log) replaces this in the next step.
struct GoalSummaryPanel: View {
    @Environment(AppModel.self) private var model
    let goal: Goal
    /// Effective progress, 0-100.
    let progress: Int

    var body: some View {
        let timeline = model.visionTimeline(goal.timelineID)
        let color = timeline?.color ?? .fallback
        let span = TimelineDates.span(type: goal.type, start: goal.startDate, target: goal.targetDate, createdAt: goal.createdAt,
                                      calendar: .current)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.s) {
                Circle().fill(Theme.Vision.color(color)).frame(width: Theme.Timeline.laneDot, height: Theme.Timeline.laneDot)
                Text(timeline?.name ?? "").font(Theme.Fonts.small).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                Spacer()
                IconButton(icon: .close, help: "Close (Esc)") {
                    model.visionBoard.openGoalID = nil
                    model.visionBoard.requestFocus()
                }
            }
            .padding(.leading, Theme.Space.l)
            .padding(.trailing, Theme.Space.s)
            .frame(height: Theme.Timeline.axisHeight)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(goal.title)
                            .font(Theme.font(Theme.TextSize.input, .medium))
                            .foregroundStyle(Theme.Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(goal.type.title) · \(span.map(VisionFormat.span) ?? "No dates")")
                            .font(Theme.Fonts.small)
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    HStack(spacing: Theme.Space.s) {
                        SectionLabel(title: "Status")
                        Spacer()
                        PopUpMenuButton(help: "Change the status") {
                            GoalStatus.allCases.map { status in
                                .item(status.title, checked: status == goal.status) { model.setStatus(goal, status) }
                            }
                        } label: {
                            HStack(spacing: Theme.Space.xs) {
                                Text(goal.status.title).font(Theme.Fonts.small).foregroundStyle(Theme.Palette.text)
                                Icon(.chevronDown, size: Theme.Size.dragHandle).foregroundStyle(Theme.Palette.textTertiary)
                            }
                        }
                        .accessibilityLabel("Status: \(goal.status.title)")
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        SectionLabel(title: "Progress", detail: "\(progress)%")
                        ProgressTrack(color: color, fraction: Double(progress) / 100)
                        if let metric = goal.metric {
                            Text(metricLine(metric))
                                .font(Theme.Fonts.small)
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .monospacedDigit()
                        }
                    }
                    if !goal.notes.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            SectionLabel(title: "Notes")
                            Text(goal.notes)
                                .font(Theme.Fonts.small)
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Hairline()
            HStack {
                Button("Delete…") { model.visionBoard.prompt = .deleteGoal(goal.id) }.buttonStyle(.ghost)
                Spacer()
            }
            .padding(Theme.Space.s)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Goal: \(goal.title)")
    }

    private func metricLine(_ m: GoalMetric) -> String {
        let unit = m.unit.isEmpty ? "" : " \(m.unit)"
        let name = m.name.isEmpty ? "" : "\(m.name): "
        return "\(name)\(m.current.formatted()) of \(m.target.formatted())\(unit)"
    }
}

/// A thin track with a tonal fill of the timeline's hue.
struct ProgressTrack: View {
    let color: TimelineColor
    let fraction: Double

    var body: some View {
        let hue = Theme.Vision.color(color)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Vision.fill(color))
                Capsule()
                    .fill(LinearGradient(colors: [hue.opacity(Theme.Vision.Alpha.progressHigh), hue], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: Theme.Space.xs)
        .accessibilityHidden(true)
    }
}
