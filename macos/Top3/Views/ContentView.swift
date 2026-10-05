import SwiftData
import SwiftUI

/// The main window: custom sidebar, a content area with its own header, and an optional calendar panel.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Query(animation: Theme.Motion.list) private var tasks: [TaskItem]
    @AppStorage("showCalendarPanel") private var showPanel = true
    @AppStorage("showSidebar") private var showSidebar = true

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            if showSidebar {
                SidebarView(tasks: tasks)
                    .frame(width: Theme.Size.sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .background(Theme.Palette.surface)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Hairline(vertical: true)
            }

            VStack(spacing: 0) {
                header
                Hairline()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(Theme.Palette.background)

            if showPanel {
                Hairline(vertical: true)
                CalendarPanel()
                    .frame(width: Theme.Size.panelWidth)
                    .frame(maxHeight: .infinity)
                    .background(Theme.Palette.surface)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .background(WindowConfigurator())
        .background(Theme.Palette.background)
        .font(Theme.Fonts.body)
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
        .sheet(item: $model.editor) { request in
            TaskEditor(request: request).presentationBackground(Theme.Palette.surface)
        }
        .sheet(item: $model.customFocusRequest) { request in
            CustomFocusSheet(request: request).presentationBackground(Theme.Palette.surface)
        }
        .sheet(isPresented: $model.showQuickPark) {
            QuickParkSheet().presentationBackground(Theme.Palette.surface)
        }
        .overlay {
            if model.showPlanning {
                PlanningView(tasks: tasks).transition(.opacity)
            }
        }
        .animation(Theme.Motion.list, value: model.showPlanning)
        .overlay {
            if model.showWrapUp {
                WrapUpView(tasks: tasks).transition(.opacity)
            }
        }
        .animation(Theme.Motion.standard, value: model.showWrapUp)
        .overlay {
            if model.showPalette {
                CommandPalette(tasks: tasks).transition(.opacity)
            }
        }
        .animation(Theme.Motion.standard, value: model.showPalette)
        .animation(Theme.Motion.list, value: showSidebar)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(text: toast.text)
                    .padding(.bottom, Theme.Space.l)
                    .transition(.opacity.combined(with: .offset(y: Theme.Space.xs)))
                    .id(toast.id)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            IconButton(icon: .sidebar, help: showSidebar ? "Hide sidebar (⌃⌘S)" : "Show sidebar (⌃⌘S)") {
                withAnimation(Theme.Motion.list) { showSidebar.toggle() }
            }
            Text(title).font(Theme.Fonts.bodyMedium).foregroundStyle(Theme.Palette.text)
            if let subtitle {
                Text(subtitle).font(Theme.Fonts.small).foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer()
            if !showSidebar { FocusTimerView(compact: true) }
            accessory
            HStack(spacing: Theme.Space.xxs) {
                IconButton(icon: .search, help: "Command palette (⌘K)") { model.showPalette = true }
                IconButton(icon: .add, help: "New task (⌘N)") { model.newTask() }
                IconButton(icon: .quickAdd, help: "Park an idea (⇧⌘P)") { model.showQuickPark = true }
                IconButton(icon: .panel, help: showPanel ? "Hide today's calendar" : "Show today's calendar",
                           active: showPanel) {
                    withAnimation(Theme.Motion.list) { showPanel.toggle() }
                }
            }
        }
        .padding(.leading, showSidebar ? Theme.Space.m : Theme.Size.trafficLights)
        .padding(.trailing, Theme.Space.m)
        .frame(height: Theme.Size.header)
        .background(WindowDragArea())
    }

    private var title: String {
        switch model.section {
        case .today: "Today"
        case let .list(l): l.title
        case .calendar: "Calendar"
        case .done: "Done"
        }
    }

    private var subtitle: String? {
        switch model.section {
        case .today, .calendar:
            return (DayKey.date(from: model.today) ?? Date()).formatted(.dateTime.weekday(.wide).month(.wide).day())
        case let .list(l) where l == .parkingLot:
            return "Ideas remind you after an hour"
        case let .list(l):
            let n = model.ordered(l, in: tasks).count
            return n == 1 ? "1 open" : "\(n) open"
        case .done:
            let n = DoneView.completed(in: tasks).count
            return n == 1 ? "1 task" : "\(n) tasks"
        }
    }

    @ViewBuilder private var accessory: some View {
        switch model.section {
        case .today:
            TodayStats(tasks: tasks).padding(.trailing, Theme.Space.s)
        case let .list(l) where l != .parkingLot:
            AutoSortControl(list: l)
        case .calendar where model.calendar.hasAccess:
            Button("Sync now") { model.syncAllEvents() }.buttonStyle(.ghost)
            Button("Open Calendar") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
            }
            .buttonStyle(.ghost)
        default:
            EmptyView()
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .today: TodayView(tasks: tasks)
        case let .list(l) where l == .parkingLot: ParkingLotView(tasks: tasks)
        case let .list(l): ListScreen(list: l, tasks: tasks)
        case .calendar: CalendarScreen()
        case .done: DoneView(tasks: tasks)
        }
    }
}
