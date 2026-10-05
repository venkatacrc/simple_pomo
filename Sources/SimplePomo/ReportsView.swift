import SwiftUI
import Charts

enum ReportPeriod: String, CaseIterable, Identifiable {
    case day, week, month, quarter, year
    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .quarter: return "Quarter"
        case .year: return "Year"
        }
    }
    var bucketComponent: Calendar.Component {
        switch self {
        case .day: return .hour
        case .week, .month: return .day
        case .quarter: return .weekOfYear
        case .year: return .month
        }
    }
    /// How the x-axis label should display each bucket
    var bucketFormatter: Date.FormatStyle {
        switch self {
        case .day: return .dateTime.hour()
        case .week: return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day().month(.abbreviated)
        case .quarter: return .dateTime.month(.abbreviated).day()
        case .year: return .dateTime.month(.abbreviated)
        }
    }
}

/// Drives the single `.sheet(item:)` used by Reports → Accomplishments for
/// adding, editing, and breaking down logged work entries.
enum AccomplishmentSheet: Identifiable {
    case editor(session: PomoSession, isNew: Bool)
    case group(date: Date, title: String, category: String)

    var id: String {
        switch self {
        case .editor(let session, let isNew):
            return "editor-\(session.id)-\(isNew)"
        case .group(let date, let title, let category):
            return "group-\(date.timeIntervalSince1970)-\(title)-\(category)"
        }
    }
}

struct ReportsView: View {
    @EnvironmentObject var store: DataStore
    @State private var period: ReportPeriod = .week
    @State private var sheet: AccomplishmentSheet?

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
                accomplishmentsSection
                allSessionsList
            }
            .padding(24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .editor(let session, let isNew):
                SessionEditorSheet(
                    session: session,
                    isNew: isNew,
                    onSave: { store.upsertSession($0) },
                    onDelete: isNew ? nil : { store.deleteSession(session) }
                )
                .environmentObject(store)
            case .group(let date, let title, let category):
                SessionGroupSheet(
                    date: date,
                    title: title,
                    category: category,
                    onEdit: { session in sheet = .editor(session: session, isNew: false) },
                    onAddMore: {
                        sheet = .editor(session: blankDraft(date: date, title: title, category: category), isNew: true)
                    }
                )
                .environmentObject(store)
            }
        }
    }

    /// A fresh, unsaved entry template for the "+" / "Add more time" flows.
    private func blankDraft(date: Date, title: String = "", category: String? = nil) -> PomoSession {
        PomoSession.manual(
            title: title,
            category: category ?? (store.settings.categories.first ?? "Quick"),
            date: date,
            minutes: 25
        )
    }

    /// Resolves a tapped Accomplishments row to either a direct single-session
    /// editor, or — if several sessions make up that total — a breakdown sheet.
    private func openEntry(date: Date, title: String, category: String) {
        let cal = Calendar.current
        let matches = sessionsInRange.filter {
            cal.isDate($0.startedAt, inSameDayAs: date) &&
            $0.taskTitle == title && $0.category == category
        }
        if matches.count == 1, let only = matches.first {
            sheet = .editor(session: only, isNew: false)
        } else {
            sheet = .group(date: date, title: title, category: category)
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
        case .year:
            let comps = cal.dateComponents([.year], from: now)
            let start = cal.date(from: comps)!
            let end = cal.date(byAdding: .year, value: 1, to: start)!.addingTimeInterval(-1)
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
            .frame(maxWidth: 400)
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
            case .month: comps = [.year, .month]
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

    // MARK: - Accomplishments journal

    /// A human-readable rollup of what you typed into the quick-capture
    /// field — grouped by day, then by task — for the selected period.
    /// This is the "what did I actually get done this week/quarter/year"
    /// view, distinct from the raw chronological session list below it.

    private struct LogEntry: Identifiable {
        let id = UUID()
        let title: String
        let category: String
        let minutes: Double
        let count: Int
    }

    private struct DayLog: Identifiable {
        let id = UUID()
        let date: Date
        let entries: [LogEntry]
        var totalMinutes: Double { entries.reduce(0) { $0 + $1.minutes } }
        var totalCount: Int { entries.reduce(0) { $0 + $1.count } }
    }

    private func accomplishmentLog() -> [DayLog] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: sessionsInRange) { cal.startOfDay(for: $0.startedAt) }
        var logs: [DayLog] = []
        for (day, daySessions) in byDay {
            let grouped = Dictionary(grouping: daySessions) { "\($0.taskTitle)|\($0.category)" }
            var entries: [LogEntry] = []
            for (_, items) in grouped {
                guard let first = items.first else { continue }
                let minutes = items.reduce(0.0) { $0 + $1.durationMinutes }
                entries.append(LogEntry(title: first.taskTitle, category: first.category,
                                        minutes: minutes, count: items.count))
            }
            entries.sort { $0.minutes > $1.minutes }
            logs.append(DayLog(date: day, entries: entries))
        }
        return logs.sorted { $0.date > $1.date }
    }

    /// A short auto-generated narrative sentence summarizing the period.
    private func highlightSummary() -> String {
        let sessions = sessionsInRange
        guard !sessions.isEmpty else {
            return "No focus sessions recorded yet this \(period.label.lowercased())."
        }
        let totalMinutes = sessions.reduce(0.0) { $0 + $1.durationMinutes }
        let distinctTasks = Set(sessions.map { $0.taskTitle }).count
        let byCategory = Dictionary(grouping: sessions, by: { $0.category })

        var text = "You logged \(sessions.count) pomodoro\(sessions.count == 1 ? "" : "s")" +
                   " (\(formatMinutes(totalMinutes))) across \(distinctTasks) task\(distinctTasks == 1 ? "" : "s")" +
                   " this \(period.label.lowercased())."

        let categoryTotals: [(name: String, minutes: Double)] = byCategory.map { key, items in
            (key, items.reduce(0.0) { $0 + $1.durationMinutes })
        }
        if byCategory.count > 1, let top = categoryTotals.max(by: { $0.minutes < $1.minutes }) {
            let pct = Int((top.minutes / totalMinutes * 100).rounded())
            text += " Most time went to \(top.name) (\(pct)%)."
        }
        return text
    }

    private func dayHeaderText(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        switch period {
        case .day, .week:
            return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        default:
            return date.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }

    private var accomplishmentsSection: some View {
        let logs = accomplishmentLog()
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accomplishments")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(highlightSummary())
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    sheet = .editor(session: blankDraft(date: Date()), isNew: true)
                } label: {
                    Label("Log work", systemImage: "plus.circle.fill")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.9))
                .help("Add something you worked on — e.g. earlier today or another day this week")
            }

            if logs.isEmpty {
                emptyChart
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(logs) { log in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(dayHeaderText(log.date))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("\(log.totalCount) 🍅 • \(formatMinutes(log.totalMinutes))")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            ForEach(log.entries) { entry in
                                Button {
                                    openEntry(date: log.date, title: entry.title, category: entry.category)
                                } label: {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color.white.opacity(0.4))
                                            .frame(width: 4, height: 4)
                                        Text(entry.title)
                                            .foregroundStyle(.white.opacity(0.92))
                                            .lineLimit(1)
                                        CategoryBadge(name: entry.category)
                                        Spacer()
                                        Text("\(entry.count) • \(formatMinutes(entry.minutes))")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.white.opacity(0.7))
                                        Image(systemName: "pencil")
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.35))
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Edit this entry")
                            }
                            if log.id != logs.last?.id {
                                Divider().opacity(0.12).padding(.top, 4)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
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
                        Image(systemName: s.isManual ? "pencil.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(s.isManual ? .white.opacity(0.6) : .red.opacity(0.8))
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
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Edit") { sheet = .editor(session: s, isNew: false) }
                        Button("Delete", role: .destructive) { store.deleteSession(s) }
                    }
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
