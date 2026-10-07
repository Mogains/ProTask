import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Panel

/// The goal detail panel beside the Vision board: everything about one goal, edited in place.
/// Title, type, timeline, dates, status and progress at the top; then the metric with its graph, notes,
/// images, linked goals and tasks, and the update log.
///
/// Images come in by drag and drop, Cmd-V while the panel has focus, or the file picker.
/// Esc closes the panel. Nothing here is shared, uploaded or logged.
struct GoalDetailPanel: View {
    @Environment(AppModel.self) private var model
    let goal: Goal
    /// Effective progress, 0-100.
    let progress: Int
    /// Linked tasks: how many, and how many are done.
    let linkedDone: Int
    let linkedTotal: Int

    @Query private var images: [GoalImage]
    @Query(sort: \VisionTimeline.sortOrder) private var timelines: [VisionTimeline]
    @FocusState private var focused: Bool
    @State private var dropTargeted = false
    @State private var importing = 0

    /// The most images taken from one drop.
    private static let dropLimit = 24

    init(goal: Goal, progress: Int, linkedDone: Int, linkedTotal: Int) {
        self.goal = goal
        self.progress = progress
        self.linkedDone = linkedDone
        self.linkedTotal = linkedTotal
        let id = goal.id
        _images = Query(filter: #Predicate<GoalImage> { $0.goalID == id }, sort: \GoalImage.sortOrder)
    }

    private var timeline: VisionTimeline? { timelines.first { $0.id == goal.timelineID } }
    private var color: TimelineColor { timeline?.color ?? .fallback }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let cover = images.first(where: { $0.id == goal.coverImageID }) { coverView(cover) }
                    titleBlock
                    properties
                    divider
                    progressSection
                    divider
                    GoalMetricSection(goal: goal, color: color)
                    divider
                    GoalNotesSection(goal: goal)
                    divider
                    GoalImagesSection(goal: goal, images: images, importing: importing, paste: paste, choose: choose)
                    divider
                    GoalLinksSection(goal: goal)
                    divider
                    GoalLogSection(goal: goal, color: color)
                }
                .padding(.bottom, Theme.Space.l)
                .background {
                    // Clicking empty space gives the panel focus, so Cmd-V adds an image.
                    Color.clear.contentShape(Rectangle()).onTapGesture { focused = true }
                }
            }
            Hairline()
            footer
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            close()
            return .handled
        }
        .onExitCommand { close() }
        .onPasteCommand(of: [.image, .fileURL, .png, .tiff]) { _ in paste() }
        .onDrop(of: [.fileURL, .image], isTargeted: $dropTargeted, perform: drop)
        .overlay { if dropTargeted { dropHighlight } }
        .sheet(item: Binding(get: { model.visionBoard.linkPicker }, set: { model.visionBoard.linkPicker = $0 })) { kind in
            GoalLinkPickerSheet(goalID: goal.id, kind: kind).presentationBackground(Theme.Palette.surface)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Goal details: \(goal.title)")
    }

    private var divider: some View {
        Hairline().padding(.horizontal, Theme.Space.l)
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            Circle().fill(Theme.Vision.color(color)).frame(width: Theme.Timeline.laneDot, height: Theme.Timeline.laneDot)
            Text(timeline?.name ?? "")
                .font(Theme.Fonts.small)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
            Spacer()
            IconButton(icon: .image, help: "Add images…", action: choose)
            IconButton(icon: .close, help: "Close (Esc)", action: close)
        }
        .padding(.leading, Theme.Space.l)
        .padding(.trailing, Theme.Space.s)
        .frame(height: Theme.Timeline.axisHeight)
    }

    private var footer: some View {
        HStack {
            Button("Delete Goal…") { model.visionBoard.prompt = .deleteGoal(goal.id) }
                .buttonStyle(.ghost)
            Spacer()
            Text("Stays on this Mac")
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.Palette.textTertiary)
                .padding(.trailing, Theme.Space.s)
        }
        .padding(Theme.Space.s)
    }

    // MARK: Cover and title

    private func coverView(_ cover: GoalImage) -> some View {
        Button { model.visionBoard.viewer = ImageViewerRequest(goalID: goal.id, imageID: cover.id) } label: {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Theme.GoalPanel.coverHeight)
                .overlay { VisionImageView(fileName: cover.fileName, placeholder: cover.thumbnailFileName) }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
                .overlay(alignment: .top) {
                    // A one-point highlight along the top edge, for a little depth.
                    RoundedRectangle(cornerRadius: Theme.Radius.m)
                        .strokeBorder(Theme.Vision.innerHighlight, lineWidth: Theme.Size.hairline)
                        .mask(alignment: .top) { Rectangle().frame(height: Theme.Space.xs) }
                }
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.border, lineWidth: Theme.Size.hairline))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.l)
        .help("Show full size")
        .accessibilityLabel("Cover image. Show full size")
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            CommitField(placeholder: "Goal title", value: goal.title, font: Theme.font(Theme.TextSize.input, .medium),
                        bordered: false, axis: .vertical, allowsEmpty: false) { title in
                model.editGoal(goal.id) { $0.title = title }
            }
            Text(subtitle)
                .font(Theme.Fonts.small)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.l)
        .padding(.bottom, Theme.Space.s)
    }

    /// "Goal · Mar 4 – Oct 12 · 7 months left"
    private var subtitle: String {
        let span = TimelineDates.span(type: goal.type, start: goal.startDate, target: goal.targetDate, createdAt: goal.createdAt,
                                      calendar: .current)
        let parts = [goal.type.title, span.map(VisionFormat.span) ?? "No dates",
                     GoalTimeLeft.describe(target: goal.targetDate, status: goal.status, today: Date())].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    // MARK: Properties

    private var properties: some View {
        VStack(spacing: 0) {
            PropertyRow(label: "Type") {
                Segments(options: GoalType.allCases, selection: binding(\.type)) { $0.title }
            }
            PropertyRow(label: "Timeline") {
                TimelineMenuPicker(timelines: timelines, selection: Binding(
                    get: { goal.timelineID },
                    set: { id in if let id { model.editGoal(goal.id) { $0.timelineID = id } } }))
            }
            PropertyRow(label: "Status") {
                PopUpMenuButton(help: "Change the status", padded: false) {
                    GoalStatus.allCases.map { status in
                        .item(status.title, checked: status == goal.status) { model.editGoal(goal.id) { $0.status = status } }
                    }
                } label: {
                    HStack(spacing: Theme.Space.s) {
                        Text(goal.status.title).font(Theme.Fonts.small).foregroundStyle(Theme.Palette.text)
                        Icon(.chevronDown, size: Theme.Size.dragHandle).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .frame(minHeight: Theme.Size.iconButton)
                }
                .accessibilityLabel("Status: \(goal.status.title)")
            }
            if goal.type != .milestone {
                PropertyRow(label: "Start") {
                    OptionalDateField(label: "Start date", date: goal.startDate, from: nil, upTo: goal.targetDate,
                                      suggested: { Calendar.current.startOfDay(for: Date()) }) { date in
                        model.editGoal(goal.id) { $0.startDate = date }
                    }
                }
            }
            PropertyRow(label: goal.type == .milestone ? "Date" : "Target") {
                OptionalDateField(label: goal.type == .milestone ? "Date" : "Target date", date: goal.targetDate,
                                  from: goal.type == .milestone ? nil : goal.startDate, upTo: nil, suggested: suggestedTarget) { date in
                    model.editGoal(goal.id) { $0.targetDate = date }
                }
            }
        }
        .padding(.bottom, Theme.Space.s)
    }

    /// Three months after the start (or today) for a goal; today for a milestone.
    private func suggestedTarget() -> Date {
        let cal = Calendar.current
        let base = cal.startOfDay(for: goal.type == .milestone ? Date() : (goal.startDate ?? Date()))
        return goal.type == .milestone ? base : (cal.date(byAdding: .month, value: 3, to: base) ?? base)
    }

    private func binding<T>(_ key: WritableKeyPath<GoalDraft, T>) -> Binding<T> {
        Binding(get: { goal.draft[keyPath: key] }, set: { value in model.editGoal(goal.id) { $0[keyPath: key] = value } })
    }

    // MARK: Progress

    private var progressSection: some View {
        let source = ProgressSource.of(mode: goal.progressMode, status: goal.status, metric: goal.metric,
                                       linkedDone: linkedDone, linkedTotal: linkedTotal)
        return PanelSection(title: "Progress", detail: "\(progress)%") {
            Segments(options: ProgressMode.allCases, selection: binding(\.progressMode)) { $0 == .auto ? "Auto" : "Manual" }
                .help("Auto uses the metric, then linked tasks")
        } content: {
            if source == .manual {
                ProgressSlider(value: goal.progress, color: color) { value in model.editGoal(goal.id) { $0.progress = value } }
            } else {
                ProgressTrack(color: color, fraction: Double(progress) / 100)
                    .padding(.vertical, (Theme.GoalPanel.sliderHeight - Theme.Space.xs) / 2)
                    .accessibilityElement()
                    .accessibilityLabel("Progress")
                    .accessibilityValue("\(progress) percent")
            }
            Text(source.explanation)
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    private func close() {
        model.visionBoard.openGoalID = nil
        model.visionBoard.requestFocus()
    }

    private func choose() { model.chooseImages(for: goal) }

    private func paste() {
        importing += 1
        Task {
            await model.pasteImage(into: goal, from: .general)
            importing -= 1
        }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        let usable = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }
        guard !usable.isEmpty else { return false }
        importing += 1
        Task {
            var sources: [VisionImageStore.Source] = []
            for provider in usable.prefix(Self.dropLimit) {
                if let source = await ImageDrop.source(from: provider) { sources.append(source) }
            }
            if sources.isEmpty {
                model.showToast(usable.count == 1 ? "That file isn't an image." : "Those files aren't images.")
            } else {
                await model.addImages(sources, to: goal)
            }
            importing -= 1
        }
        return true
    }

    private var dropHighlight: some View {
        let accent = Theme.Palette.accent
        return RoundedRectangle(cornerRadius: Theme.Radius.m)
            .fill(accent.opacity(Theme.Vision.Alpha.dropFill))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(accent, lineWidth: Theme.GoalPanel.dropStroke))
            .overlay {
                HStack(spacing: Theme.Space.s) {
                    Icon(.image)
                    Text("Drop to add to this goal")
                }
                .font(Theme.Fonts.small)
                .foregroundStyle(Theme.Palette.text)
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.s)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.elevated))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.border, lineWidth: Theme.Size.hairline))
            }
            .padding(Theme.Space.xs)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Dropped images

/// Reads what was dropped: an image file (by its content type) or image data from another app.
enum ImageDrop {
    static func source(from provider: NSItemProvider) async -> VisionImageStore.Source? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL? = await withCheckedContinuation { done in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in done.resume(returning: url) }
            }
            guard let url, url.isFileURL,
                  let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType, type.conforms(to: .image)
            else { return nil }
            return .file(url)
        }
        let data: Data? = await withCheckedContinuation { done in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in done.resume(returning: data) }
        }
        return data.map { .data($0) }
    }
}

// MARK: - Building blocks

/// A titled block of the panel: a small label, an optional control on the right, then the content.
struct PanelSection<Trailing: View, Content: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                SectionLabel(title: title, detail: detail)
                Spacer(minLength: 0)
                trailing()
            }
            .frame(minHeight: Theme.Size.iconButton)
            content()
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

extension PanelSection where Trailing == EmptyView {
    init(title: String, detail: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, detail: detail, trailing: { EmptyView() }, content: content)
    }
}

/// A text field that saves when you press Return, leave it, or close the panel; not on every keystroke.
/// It follows outside changes while you aren't typing in it.
struct CommitField: View {
    let placeholder: String
    let value: String
    var font: Font = Theme.Fonts.small
    var bordered = true
    var axis: Axis = .horizontal
    var alignment: TextAlignment = .leading
    /// False refuses an empty value and puts the old one back.
    var allowsEmpty = true
    /// Text that fails this goes back to the old value.
    var isValid: (String) -> Bool = { _ in true }
    let commit: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.Palette.textTertiary), axis: axis)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(Theme.Palette.text)
            .multilineTextAlignment(alignment)
            .focused($focused)
            .focusEffectDisabled()
            .onSubmit(finish)
            .padding(.horizontal, bordered ? Theme.Space.s : 0)
            .padding(.vertical, bordered ? Theme.Space.s - Theme.Space.xxs : 0)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.m)
                .strokeBorder(bordered ? (focused ? Theme.Palette.textTertiary : Theme.Palette.border) : .clear,
                              lineWidth: Theme.Size.hairline))
            .animation(Theme.Motion.hover, value: focused)
            .onAppear { text = value }
            .onChange(of: value) { if !focused { text = value } }
            .onChange(of: focused) { if !focused { finish() } }
            .onDisappear(perform: finish)
            .accessibilityLabel(placeholder)
    }

    private func finish() {
        guard text != value else { return }
        if (!allowsEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || !isValid(text) {
            text = value
            return
        }
        commit(text)
    }
}

/// A date that can be unset: "Set date" until there is one, then a date field and Clear.
struct OptionalDateField: View {
    let label: String
    let date: Date?
    /// The earliest and latest allowed days, so the start never passes the target.
    let from: Date?
    let upTo: Date?
    let suggested: () -> Date
    let set: (Date?) -> Void

    var body: some View {
        if let date {
            HStack(spacing: Theme.Space.s) {
                picker(date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .font(Theme.Fonts.small)
                    .accessibilityLabel(label)
                Spacer()
                Button("Clear") { set(nil) }
                    .buttonStyle(.ghost)
                    .accessibilityLabel("Clear \(label.lowercased())")
            }
        } else {
            Button("Set date") { set(clamped(suggested())) }
                .buttonStyle(.ghost)
                .accessibilityLabel("Set \(label.lowercased())")
        }
    }

    @ViewBuilder
    private func picker(_ date: Date) -> some View {
        let binding = Binding(get: { date }, set: { set(Calendar.current.startOfDay(for: $0)) })
        if let from, let upTo {
            DatePicker(label, selection: binding, in: from...max(from, upTo), displayedComponents: .date)
        } else if let from {
            DatePicker(label, selection: binding, in: from..., displayedComponents: .date)
        } else if let upTo {
            DatePicker(label, selection: binding, in: ...upTo, displayedComponents: .date)
        } else {
            DatePicker(label, selection: binding, displayedComponents: .date)
        }
    }

    private func clamped(_ d: Date) -> Date {
        var d = d
        if let from, d < from { d = from }
        if let upTo, d > upTo { d = upTo }
        return d
    }
}

/// Manual progress: drag the knob, or use the arrow keys (5 at a time, 1 with Shift).
struct ProgressSlider: View {
    let value: Int
    let color: TimelineColor
    let commit: (Int) -> Void

    @State private var dragValue: Int?
    @FocusState private var focused: Bool

    private static let step = 5

    var body: some View {
        let shown = dragValue ?? value
        let knob = Theme.GoalPanel.sliderKnob
        GeometryReader { geo in
            let usable = max(geo.size.width - knob, 1)
            ZStack(alignment: .leading) {
                ProgressTrack(color: color, fraction: Double(shown) / 100)
                    .padding(.horizontal, knob / 2)
                Circle()
                    .fill(Theme.Palette.elevated)
                    .overlay(Circle().strokeBorder(focused ? Theme.Palette.accent : Theme.Palette.textTertiary, lineWidth: Theme.Size.hairline))
                    .shadow(color: Theme.Palette.shadow, radius: Theme.Size.hairline, y: Theme.Size.hairline / 2)
                    .frame(width: knob, height: knob)
                    .offset(x: usable * CGFloat(shown) / 100)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    focused = true
                    dragValue = GoalProgress.clamp(Double((g.location.x - knob / 2) / usable * 100))
                }
                .onEnded { _ in
                    if let v = dragValue, v != value { commit(v) }
                    dragValue = nil
                })
        }
        .frame(height: Theme.GoalPanel.sliderHeight)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .downArrow, .upArrow]) { press in
            let up = press.key == .rightArrow || press.key == .upArrow
            nudge((press.modifiers.contains(.shift) ? 1 : Self.step) * (up ? 1 : -1))
            return .handled
        }
        .help("Drag, or use the arrow keys (Shift for 1%)")
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(shown) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(Self.step)
            case .decrement: nudge(-Self.step)
            @unknown default: break
            }
        }
    }

    private func nudge(_ delta: Int) {
        let next = GoalProgress.clamp(value + delta)
        if next != value { commit(next) }
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
