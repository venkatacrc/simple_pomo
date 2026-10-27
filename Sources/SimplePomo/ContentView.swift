import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var timer: PomodoroTimer
    @EnvironmentObject var windows: WindowController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selectedTab: Tab = .focus

    enum Tab: String, Hashable, CaseIterable, Identifiable {
        case focus, tasks, plan, reports
        var id: String { rawValue }
        var label: String {
            switch self {
            case .focus: return "Focus"
            case .tasks: return "Tasks"
            case .plan: return "Plan"
            case .reports: return "Reports"
            }
        }
        var symbol: String {
            switch self {
            case .focus: return "timer"
            case .tasks: return "checklist"
            case .plan: return "calendar"
            case .reports: return "chart.bar.xaxis"
            }
        }
    }

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: timer.phase)

            VStack(spacing: 0) {
                header
                Divider().opacity(0.25)
                content
            }
        }
        .preferredColorScheme(.dark)
    }

    private var backgroundGradient: some View {
        let base = timer.phase.accentBackground
        return LinearGradient(
            colors: [
                base.opacity(0.95),
                base.opacity(0.7),
                Color.black.opacity(0.9)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var header: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "leaf.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                Text("Simple Pomo")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                currentWeekBadge
            }

            Spacer()

            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Label(tab.label, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 440)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("\(todayPomodoroCount)")
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("today")
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.callout)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.12), in: Capsule())

            Button {
                windows.enterMini(open: openWindow, dismiss: dismissWindow)
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Shrink to floating mini timer (⌘⇧M)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .focus:
            FocusView()
        case .tasks:
            TaskListView()
        case .plan:
            PlanView()
        case .reports:
            ReportsView()
        }
    }

    private var todayPomodoroCount: Int {
        let cal = Calendar.current
        return store.sessions.filter {
            $0.phase == .focus && cal.isDateInToday($0.startedAt)
        }.count
    }

    /// Shows the active calendar week next to the logo, e.g. "Week of Oct 20".
    private var currentWeekBadge: some View {
        let cal = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let start = cal.date(from: comps) ?? Date()
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        let weekNum = comps.weekOfYear ?? 0
        return HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.caption)
            VStack(alignment: .leading, spacing: 0) {
                Text("Week \(weekNum)")
                    .font(.caption.weight(.semibold))
                Text("\(start.formatted(.dateTime.month(.abbreviated).day()))–\(end.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.white.opacity(0.12), in: Capsule())
        .help("Current week: \(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))")
    }
}
