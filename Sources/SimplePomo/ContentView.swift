import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var timer: PomodoroTimer
    @State private var selectedTab: Tab = .focus

    enum Tab: String, Hashable, CaseIterable, Identifiable {
        case focus, tasks, reports
        var id: String { rawValue }
        var label: String {
            switch self {
            case .focus: return "Focus"
            case .tasks: return "Tasks"
            case .reports: return "Reports"
            }
        }
        var symbol: String {
            switch self {
            case .focus: return "timer"
            case .tasks: return "checklist"
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
            HStack(spacing: 8) {
                Image(systemName: "leaf.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                Text("Simple Pomo")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Spacer()

            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Label(tab.label, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)

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
}
