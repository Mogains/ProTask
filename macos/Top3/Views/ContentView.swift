import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Query(animation: .snappy) private var tasks: [TaskItem]
    @AppStorage("showCalendarPanel") private var showPanel = true

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView(tasks: tasks)
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.content)
                .inspector(isPresented: $showPanel) {
                    CalendarPanel().inspectorColumnWidth(min: 210, ideal: 240, max: 320)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { model.newTask() } label: { Label("New Task", systemImage: "plus") }
                            .help("New task (Command-N)")
                        Button { model.showQuickPark = true } label: { Label("Park an Idea", systemImage: "lightbulb") }
                            .help("Quick add to Parking Lot (Shift-Command-P)")
                        Button { showPanel.toggle() } label: { Label("Today's Calendar", systemImage: "sidebar.right") }
                            .help(showPanel ? "Hide today's calendar" : "Show today's calendar")
                    }
                }
        }
        .navigationTitle(title)
        .sheet(item: $model.editor) { TaskEditor(request: $0) }
        .sheet(isPresented: $model.showQuickPark) { QuickParkSheet() }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(text: toast.text)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
            }
        }
        .overlay {
            if model.celebrating {
                CelebrationView().transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .today: TodayView(tasks: tasks)
        case let .list(l) where l == .parkingLot: ParkingLotView(tasks: tasks)
        case let .list(l): ListScreen(list: l, tasks: tasks)
        case .calendar: CalendarScreen()
        case .done: DoneView(tasks: tasks)
        }
    }

    private var title: String {
        switch model.section {
        case .today: "Today"
        case let .list(l): l.title
        case .calendar: "Calendar"
        case .done: "Done"
        }
    }
}

struct ToastView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.secondary.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}

/// A short, quiet celebration: a seal and a ring of dots that drift outward.
struct CelebrationView: View {
    @State private var burst = false

    var body: some View {
        ZStack {
            ForEach(0..<16, id: \.self) { i in
                let angle = Double(i) / 16 * 2 * .pi
                Circle()
                    .fill(Color.accentColor.opacity(i.isMultiple(of: 2) ? 0.7 : 0.35))
                    .frame(width: 5, height: 5)
                    .offset(x: burst ? cos(angle) * 90 : 0, y: burst ? sin(angle) * 90 : 0)
                    .opacity(burst ? 0 : 1)
            }
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.bounce, value: burst)
                Text("All three done").font(Theme.bodyMedium)
                Text("That's the day's work.").font(Theme.secondary).foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline))
        }
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 1.1)) { burst = true } }
    }
}
