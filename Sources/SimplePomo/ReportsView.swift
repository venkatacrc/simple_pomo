import SwiftUI
import Charts

enum ReportPeriod: String, CaseIterable, Identifiable {
    case day, week, month, quarter
    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .quarter: return "Quarter"
        }
    }
    var bucketComponent: Calendar.Component {
        switch self {
        case .day: return .hour
        case .week, .month: return .day
        case .quarter: return .weekOfYear
        }
    }
    /// How the x-axis label should display each bucket
    var bucketFormatter: Date.FormatStyle {
        switch self {
        case .day: return .dateTime.hour()
        case .week: return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day().month(.abbreviated)
        case .quarter: return .dateTime.month(.abbreviated).day()
        }
    }
}

struct ReportsView: View {
    @EnvironmentObject var store: DataStore
    @State private var period: ReportPeriod = .week

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                summaryCards
                focusOverTimeChart
                HStack(alignment: .top, spacing: 18) {
                    categoryChart
                    topTasks
                }
                allSessionsList
            }
            .padding(24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Filter helpers

    private var range: ClosedRange<Date> {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .day:
            let start = cal.startOfDay(for: now)
            let end = cal.date(byAdding: .day, value: 1, to: start)!.addingTimeInterval(-1)
            return start...end
        case .week:
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            let start = cal.date(from: comps)!
            let end = cal.date(byAdding: .day, value: 7, to: start)!.addingTimeInterval(-1)
            return start...end
        case .month:
            let comps = cal.dateComponents([.year, .month], from: now)
            let start = cal.date(from: comps)!
            let end = cal.date(byAdding: .month, value: 1, to: start)!.addingTimeInterval(-1)
            return start...end
        case .quarter:
            let comps = cal.dateComponents([.year, .month], from: now)
            let month = comps.month ?? 1
            let qStartMonth = ((month - 1) / 3) * 3 + 1
            var qComps = DateComponents()
            qComps.year = comps.year
            qComps.month = qStartMonth
            qComps.day = 1
            let start = cal.date(from: qComps)!
            let end = cal.date(byAdding: .month, value: 3, to: start)!.addingTimeInterval(-1)
            return start...end
        }
    }

    private var sessionsInRange: [PomoSession] {
        let r = range
        return store.sessions.filter {
            $0.phase == .focus && $0.startedAt >= r.lowerBound && $0.startedAt <= r.upperBound
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Reports")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Spacer()
            Picker("", selection: $period) {
                ForEach(ReportPeriod.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
        }
    }

    // MARK: - Summary cards

    private var summaryCards: some View {
        let sessions = sessionsInRange
        let totalMinutes = sessions.reduce(0.0) { $0 + $1.durationMinutes }
        let categories = Set(sessions.map { $0.category }).count
        let avgPerDay = avgFocusPerDay(sessions: sessions)
        return HStack(spacing: 12) {
            statCard(title: "Pomodoros", value: "\(sessions.count)", systemImage: "checkmark.seal.fill", tint: .red)
            statCard(title: "Focus time", value: formatMinutes(totalMinutes), systemImage: "hourglass", tint: .orange)
            statCard(title: "Avg / day", value: formatMinutes(avgPerDay), systemImage: "calendar", tint: .teal)
            statCard(title: "Categories", value: "\(categories)", systemImage: "square.grid.2x2.fill", tint: .purple)
        }
    }

    private func avgFocusPerDay(sessions: [PomoSession]) -> Double {
        guard !sessions.isEmpty else { return 0 }
        let cal = Calendar.current
        let days = Set(sessions.map { cal.startOfDay(for: $0.startedAt) })
        let total = sessions.reduce(0.0) { $0 + $1.durationMinutes }
        return days.isEmpty ? 0 : total / Double(days.count)
    }

    private func statCard(title: String, value: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    // MARK: - Focus over time chart

    private struct Bucket: Identifiable {
        let id = UUID()
        let date: Date
        let category: String
        let minutes: Double
    }

    private var buckets: [Bucket] {
        let cal = Calendar.current
        let component = period.bucketComponent
        let grouped = Dictionary(grouping: sessionsInRange) { session -> Date in
            let comps: Set<Calendar.Component>
            switch component {
            case .hour: comps = [.year, .month, .day, .hour]
            case .day: comps = [.year, .month, .day]
            case .weekOfYear: comps = [.yearForWeekOfYear, .weekOfYear]
            default: comps = [.year, .month, .day]
            }
            return cal.date(from: cal.dateComponents(comps, from: session.startedAt)) ?? session.startedAt
        }
        var out: [Bucket] = []
        for (date, sessionsAtBucket) in grouped {
            let byCat = Dictionary(grouping: sessionsAtBucket) { $0.category }
            for (cat, items) in byCat {
                let mins = items.reduce(0.0) { $0 + $1.durationMinutes }
                out.append(Bucket(date: date, category: cat, minutes: mins))
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    private var focusOverTimeChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Focus minutes — by \(period.label.lowercased())")
                .font(.headline)
                .foregroundStyle(.white)
            if buckets.isEmpty {
                emptyChart
            } else {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Bucket", bucket.date, unit: period.bucketComponent),
                        y: .value("Minutes", bucket.minutes)
                    )
                    .foregroundStyle(by: .value("Category", bucket.category))
                    .cornerRadius(4)
                }
                .chartForegroundStyleScale(range: chartPalette)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 8)) { value in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel(format: period.bucketFormatter)
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel().foregroundStyle(Color.white.opacity(0.8))
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 260)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    // MARK: - Category breakdown (donut)

    private struct CategorySlice: Identifiable {
        let id = UUID()
        let category: String
        let minutes: Double
        let count: Int
    }

    private var categorySlices: [CategorySlice] {
        let grouped = Dictionary(grouping: sessionsInRange, by: { $0.category })
        return grouped.map { key, value in
            CategorySlice(category: key,
                          minutes: value.reduce(0.0) { $0 + $1.durationMinutes },
                          count: value.count)
        }
        .sorted { $0.minutes > $1.minutes }
    }

    private var categoryChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By category")
                .font(.headline)
                .foregroundStyle(.white)
            if categorySlices.isEmpty {
                emptyChart
            } else {
                Chart(categorySlices) { slice in
                    SectorMark(
                        angle: .value("Minutes", slice.minutes),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(by: .value("Category", slice.category))
                    .cornerRadius(4)
                }
                .chartForegroundStyleScale(range: chartPalette)
                .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
                .frame(height: 220)

                VStack(spacing: 4) {
                    ForEach(categorySlices.prefix(5)) { slice in
                        HStack {
                            CategoryBadge(name: slice.category)
                            Spacer()
                            Text("\(slice.count) • \(formatMinutes(slice.minutes))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    // MARK: - Top tasks

    private var topTasks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top tasks")
                .font(.headline)
                .foregroundStyle(.white)
            let rows = topTaskRows()
            if rows.isEmpty {
                emptyChart
            } else {
                VStack(spacing: 6) {
                    ForEach(rows) { row in
                        HStack {
                            Text(row.title)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer()
                            Text("\(row.count) • \(formatMinutes(row.minutes))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.vertical, 4)
                        Divider().opacity(0.15)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    private struct TaskRow: Identifiable {
        let id = UUID()
        let title: String
        let minutes: Double
        let count: Int
    }

    private func topTaskRows() -> [TaskRow] {
        let grouped = Dictionary(grouping: sessionsInRange, by: { $0.taskTitle })
        var rows: [TaskRow] = []
        for (title, items) in grouped {
            let minutes = items.reduce(0.0) { $0 + $1.durationMinutes }
            rows.append(TaskRow(title: title, minutes: minutes, count: items.count))
        }
        rows.sort { $0.minutes > $1.minutes }
        return Array(rows.prefix(8))
    }

    // MARK: - Recent sessions list

    private var allSessionsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent sessions")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(sessionsInRange.count) in \(period.label.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            let recent = sessionsInRange.sorted { $0.startedAt > $1.startedAt }.prefix(20)
            if recent.isEmpty {
                Text("No focus sessions yet for this period.")
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                ForEach(Array(recent), id: \.id) { s in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.red.opacity(0.8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.taskTitle)
                                .foregroundStyle(.white)
                            HStack(spacing: 8) {
                                CategoryBadge(name: s.category)
                                Text(s.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        Spacer()
                        Text(formatMinutes(s.durationMinutes))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    .padding(.vertical, 6)
                    Divider().opacity(0.15)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    // MARK: - Helpers

    private var emptyChart: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.35))
            Text("No data in this range.")
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private var chartPalette: [Color] {
        [
            Color(red: 0.93, green: 0.42, blue: 0.42),
            Color(red: 0.35, green: 0.74, blue: 0.65),
            Color(red: 0.40, green: 0.60, blue: 0.86),
            Color(red: 0.95, green: 0.70, blue: 0.30),
            Color(red: 0.68, green: 0.48, blue: 0.86),
            Color(red: 0.40, green: 0.74, blue: 0.50),
            Color(red: 0.95, green: 0.55, blue: 0.70),
            Color(red: 0.55, green: 0.85, blue: 0.86)
        ]
    }

    private func formatMinutes(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total)m" }
        let h = total / 60
        let m = total % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
