import SwiftUI

/// Plan tasks for upcoming days and compare what you planned vs what you
/// actually completed (focus sessions) over the selected week.
struct PlanView: View {
    @EnvironmentObject var store: DataStore
    @State private var weekOffset: Int = 0
    @State private var showingAdd = false
    @State private var draftTitle = ""
    @State private var draftCategory = "Work"
    @State private var draftEstimate = 1
    @State private var draftDay = Date()
    @State private var draftUntil = Date()
    @State private var draftNotes = ""
    @State private var draftMultiDay = false
    @State private var editingTask: PomoTask?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                weekNav
                addPlannedCard
                comparisonSection
                dayBreakdown
            }
            .padding(24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showingAdd) {
            addSheet
                .environmentObject(store)
        }
        .sheet(item: $editingTask) { task in
            editPlannedSheet(task)
                .environmentObject(store)
        }
    }

    // MARK: - Range helpers

    private var weekRange: ClosedRange<Date> {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        let thisWeekStart = cal.date(from: comps) ?? today
        let start = cal.date(byAdding: .weekOfYear, value: weekOffset, to: thisWeekStart) ?? thisWeekStart
        let end = cal.date(byAdding: .day, value: 7, to: start)!.addingTimeInterval(-1)
        return start...end
    }

    private var weekDays: [Date] {
        let cal = Calendar.current
        let start = weekRange.lowerBound
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekLabel: String {
        let start = weekRange.lowerBound
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        let fmt = Date.FormatStyle().month(.abbreviated).day()
        return "\(start.formatted(fmt)) – \(end.formatted(fmt))"
    }

    private var plannedThisWeek: [PomoTask] {
        store.plannedTasks(in: weekRange)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Plan")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("Schedule work ahead, then compare against what you finished.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Button {
                draftDay = Date()
                draftUntil = Date()
                draftMultiDay = false
                draftTitle = ""
                draftNotes = ""
                draftEstimate = 1
                draftCategory = store.settings.categories.first ?? "Work"
                showingAdd = true
            } label: {
                Label("Plan a task", systemImage: "plus.circle.fill")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
    }

    private var weekNav: some View {
        HStack {
            Button {
                weekOffset -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)

            Spacer()
            VStack(spacing: 2) {
                Text(weekOffset == 0 ? "This week" : weekOffset == -1 ? "Last week" : weekOffset == 1 ? "Next week" : "Week")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(weekLabel)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()

            Button {
                weekOffset += 1
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)

            if weekOffset != 0 {
                Button("Today") { weekOffset = 0 }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.leading, 8)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    // MARK: - Quick add strip

    private var addPlannedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.plus")
                    .foregroundStyle(.white.opacity(0.7))
                TextField("What do you plan to work on?", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .onSubmit(quickAdd)
                Toggle("Multi-day", isOn: $draftMultiDay)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help("Plan this task across several days")
                Text(draftMultiDay ? "Multi-day" : "One day")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                DatePicker(draftMultiDay ? "From" : "", selection: $draftDay, displayedComponents: .date)
                    .labelsHidden()
                    .colorScheme(.dark)
                if draftMultiDay {
                    Text("→")
                        .foregroundStyle(.white.opacity(0.5))
                    DatePicker("Until", selection: $draftUntil, in: draftDay..., displayedComponents: .date)
                        .labelsHidden()
                        .colorScheme(.dark)
                }
                Stepper("\(draftEstimate) 🍅", value: $draftEstimate, in: 1...20)
                    .foregroundStyle(.white)
                    .frame(maxWidth: 110)
                Button("Add", action: quickAdd)
                    .disabled(draftTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.25))
            }
            Text("Tip: turn on Multi-day to schedule one task across several days (e.g. Mon→Wed).")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    private func quickAdd() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var task = PomoTask(
            title: trimmed,
            category: draftCategory,
            estimatedPomodoros: draftEstimate
        )
        task.appendNote(draftNotes)
        let end = draftMultiDay ? max(draftUntil, draftDay) : draftDay
        store.planTask(task, from: draftDay, until: end)
        draftTitle = ""
        draftNotes = ""
        draftEstimate = 1
        draftMultiDay = false
        draftUntil = draftDay
    }

    private func plannedSpanLabel(for task: PomoTask) -> String? {
        guard let range = task.plannedDayRange else { return nil }
        let fmt = Date.FormatStyle().month(.abbreviated).day()
        if Calendar.current.isDate(range.lowerBound, inSameDayAs: range.upperBound) {
            return range.lowerBound.formatted(fmt)
        }
        return "\(range.lowerBound.formatted(fmt))–\(range.upperBound.formatted(fmt))"
    }

    // MARK: - Comparison

    private struct ComparisonRow: Identifiable {
        let id: UUID
        let title: String
        let category: String
        let planned: Bool
        let estimated: Int
        let actualSessions: Int
        let actualMinutes: Double
        let notes: String
        let status: Status

        enum Status: String {
            case done, partial, missed, unplanned
            var label: String {
                switch self {
                case .done: return "Done"
                case .partial: return "Partial"
                case .missed: return "Missed"
                case .unplanned: return "Unplanned"
                }
            }
            var tint: Color {
                switch self {
                case .done: return .green
                case .partial: return .orange
                case .missed: return .red.opacity(0.85)
                case .unplanned: return .cyan
                }
            }
        }
    }

    private var comparisonRows: [ComparisonRow] {
        let range = weekRange
        var rows: [ComparisonRow] = []
        var coveredTitles = Set<String>()

        for task in plannedThisWeek {
            let sessions = store.focusSessionCount(for: task, in: range)
            let minutes = store.focusMinutes(for: task, in: range)
            let status: ComparisonRow.Status
            if task.isCompleted || sessions >= max(task.estimatedPomodoros, 1) {
                status = .done
            } else if sessions > 0 || minutes > 0 {
                status = .partial
            } else {
                status = .missed
            }
            rows.append(ComparisonRow(
                id: task.id,
                title: task.title,
                category: task.category,
                planned: true,
                estimated: task.estimatedPomodoros,
                actualSessions: sessions,
                actualMinutes: minutes,
                notes: task.notesLog,
                status: status
            ))
            coveredTitles.insert(task.title.lowercased())
        }

        // Unplanned work that still got focus time this week
        let sessions = store.sessions.filter {
            $0.phase == .focus &&
            $0.startedAt >= range.lowerBound && $0.startedAt <= range.upperBound
        }
        let byTitle = Dictionary(grouping: sessions, by: { $0.taskTitle })
        for (title, items) in byTitle {
            guard !coveredTitles.contains(title.lowercased()) else { continue }
            let minutes = items.reduce(0.0) { $0 + $1.durationMinutes }
            rows.append(ComparisonRow(
                id: items.first?.id ?? UUID(),
                title: title,
                category: items.first?.category ?? "Quick",
                planned: false,
                estimated: 0,
                actualSessions: items.count,
                actualMinutes: minutes,
                notes: "",
                status: .unplanned
            ))
        }

        return rows.sorted {
            statusRank($0.status) < statusRank($1.status) ||
            ($0.status == $1.status && $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending)
        }
    }

    private func statusRank(_ s: ComparisonRow.Status) -> Int {
        switch s {
        case .missed: return 0
        case .partial: return 1
        case .done: return 2
        case .unplanned: return 3
        }
    }

    private var comparisonSection: some View {
        let rows = comparisonRows
        let plannedCount = rows.filter(\.planned).count
        let doneCount = rows.filter { $0.status == .done }.count
        let missedCount = rows.filter { $0.status == .missed }.count
        let unplannedCount = rows.filter { $0.status == .unplanned }.count

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Planned vs completed")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(doneCount)/\(plannedCount) planned done · \(missedCount) missed · \(unplannedCount) unplanned")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }

            if plannedCount > 0 {
                ProgressView(value: Double(doneCount), total: Double(max(plannedCount, 1)))
                    .tint(.green)
            }

            if rows.isEmpty {
                Text("Nothing planned or logged this week yet. Add a planned task above.")
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 6) {
                    comparisonHeader
                    ForEach(rows) { row in
                        comparisonRow(row)
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

    private var comparisonHeader: some View {
        HStack {
            Text("Task").frame(maxWidth: .infinity, alignment: .leading)
            Text("Plan 🍅").frame(width: 88)
            Text("Done").frame(width: 50)
            Text("Time").frame(width: 60)
            Text("Status").frame(width: 72, alignment: .trailing)
            Text("").frame(width: 64)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white.opacity(0.5))
        .padding(.horizontal, 8)
    }

    private func comparisonRow(_ row: ComparisonRow) -> some View {
        let isActive = store.activeTaskId == row.id
        let task = store.tasks.first(where: { $0.id == row.id })
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.title)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if isActive {
                        Text("ACTIVE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.yellow)
                    }
                }
                HStack(spacing: 6) {
                    CategoryBadge(name: row.category)
                    if let task, let span = plannedSpanLabel(for: task) {
                        Text(span)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.cyan.opacity(0.9))
                    }
                    if !row.notes.isEmpty {
                        Text(row.notes)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Editable planned pomodoro count (− N +)
            if row.planned, let task {
                HStack(spacing: 2) {
                    Button {
                        adjustEstimate(task, by: -1)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.white.opacity(task.estimatedPomodoros > 1 ? 0.85 : 0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(task.estimatedPomodoros <= 1)
                    .help("Fewer planned pomodoros")

                    Text("\(task.estimatedPomodoros)")
                        .monospacedDigit()
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 20)
                        .onTapGesture { editingTask = task }
                        .help("Click to edit plan details")

                    Button {
                        adjustEstimate(task, by: 1)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.white.opacity(task.estimatedPomodoros < 40 ? 0.85 : 0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(task.estimatedPomodoros >= 40)
                    .help("More planned pomodoros")
                }
                .frame(width: 88)
            } else {
                Text("—")
                    .monospacedDigit()
                    .frame(width: 88)
                    .foregroundStyle(.white.opacity(0.85))
            }

            Text("\(row.actualSessions)")
                .monospacedDigit()
                .frame(width: 50)
                .foregroundStyle(.white.opacity(0.85))

            Text(formatMinutes(row.actualMinutes))
                .monospacedDigit()
                .frame(width: 60)
                .foregroundStyle(.white.opacity(0.85))

            Text(row.status.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(row.status.tint)
                .frame(width: 72, alignment: .trailing)

            if row.planned, task != nil {
                Button {
                    startWorking(onTaskId: row.id)
                } label: {
                    Label(isActive ? "Active" : "Start", systemImage: isActive ? "target" : "play.fill")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(isActive ? .yellow.opacity(0.35) : .white.opacity(0.22))
                .foregroundStyle(.white)
                .frame(width: 64)
                .help(isActive ? "Already the active Focus task" : "Pick up this planned task on the Focus tab")
            } else {
                Color.clear.frame(width: 64)
            }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color.yellow.opacity(0.12) : Color.white.opacity(0.04))
        )
        .contextMenu {
            if let task {
                Button("Edit plan…") { editingTask = task }
                Button("Start working") { startWorking(onTaskId: task.id) }
                Button("Remove from plan") { store.unplanTask(task) }
                Button("Mark completed") {
                    var t = task
                    t.isCompleted = true
                    store.updateTask(t)
                }
            }
        }
    }

    private func adjustEstimate(_ task: PomoTask, by delta: Int) {
        var t = task
        t.estimatedPomodoros = min(40, max(1, t.estimatedPomodoros + delta))
        store.updateTask(t)
    }

    /// Sets the planned task as the active Focus target so the next pomodoro
    /// is logged against it (title, category, notes, and estimates included).
    private func startWorking(onTaskId id: UUID) {
        store.activeTaskId = id
        if let task = store.tasks.first(where: { $0.id == id }), task.isCompleted {
            var t = task
            t.isCompleted = false
            store.updateTask(t)
        }
    }

    // MARK: - Day breakdown

    private var dayBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By day")
                .font(.headline)
                .foregroundStyle(.white)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(weekDays, id: \.self) { day in
                    dayCard(day)
                }
            }
        }
    }

    private func dayCard(_ day: Date) -> some View {
        let planned = store.plannedTasks(on: day)
        let isToday = Calendar.current.isDateInToday(day)
        return VStack(alignment: .leading, spacing: 6) {
            Text(day, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.caption.weight(.semibold))
                .foregroundStyle(isToday ? .yellow : .white.opacity(0.8))
            if planned.isEmpty {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach(planned.prefix(4)) { task in
                    Button {
                        startWorking(onTaskId: task.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: store.activeTaskId == task.id ? "target" : "play.circle")
                                .font(.caption2)
                            Text(task.title)
                                .lineLimit(1)
                        }
                        .font(.caption2)
                        .foregroundStyle(store.activeTaskId == task.id ? .yellow : .white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("Start working on “\(task.title)”")
                }
                if planned.count > 4 {
                    Text("+\(planned.count - 4) more")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
            Button {
                draftDay = day
                showingAdd = true
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(10)
        .frame(minHeight: 110, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isToday ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
        )
    }

    // MARK: - Edit planned task sheet

    private func editPlannedSheet(_ task: PomoTask) -> some View {
        EditPlannedTaskSheet(task: task) { updated in
            store.updateTask(updated)
            editingTask = nil
        } onCancel: {
            editingTask = nil
        }
    }

    // MARK: - Add sheet

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Plan a task")
                .font(.title3.weight(.semibold))
            Form {
                TextField("Title", text: $draftTitle)
                Picker("Category", selection: $draftCategory) {
                    ForEach(store.settings.categories, id: \.self) { Text($0).tag($0) }
                }
                Toggle("Spans multiple days", isOn: $draftMultiDay)
                DatePicker(draftMultiDay ? "Starts" : "Day", selection: $draftDay, displayedComponents: .date)
                if draftMultiDay {
                    DatePicker("Ends", selection: $draftUntil, in: draftDay..., displayedComponents: .date)
                }
                Stepper("Estimated pomodoros: \(draftEstimate)", value: $draftEstimate, in: 1...20)
                VStack(alignment: .leading) {
                    Text("Notes").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $draftNotes)
                        .frame(minHeight: 70)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { showingAdd = false }
                Button("Add to plan") {
                    quickAdd()
                    showingAdd = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 420)
    }

    private func formatMinutes(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total)m" }
        let h = total / 60
        let m = total % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)m"
    }
}

// MARK: - Edit planned task

private struct EditPlannedTaskSheet: View {
    @State private var title: String
    @State private var category: String
    @State private var estimate: Int
    @State private var newNote: String = ""
    @State private var start: Date
    @State private var end: Date
    @State private var multiDay: Bool

    let categories: [String]
    let onSave: (PomoTask) -> Void
    let onCancel: () -> Void
    private let original: PomoTask

    init(task: PomoTask, onSave: @escaping (PomoTask) -> Void, onCancel: @escaping () -> Void) {
        self.original = task
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: task.title)
        _category = State(initialValue: task.category)
        _estimate = State(initialValue: task.estimatedPomodoros)
        _newNote = State(initialValue: "")
        let startDay = task.plannedFor ?? Date()
        let endDay = task.plannedUntil ?? startDay
        _start = State(initialValue: startDay)
        _end = State(initialValue: endDay)
        _multiDay = State(initialValue: task.plannedUntil != nil &&
                          !Calendar.current.isDate(startDay, inSameDayAs: endDay))
        self.categories = {
            ["Work", "Study", "Personal", "Reading", "Side Project", "Quick"]
        }()
    }

    @EnvironmentObject var store: DataStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit planned task")
                .font(.title3.weight(.semibold))
            Form {
                TextField("Title", text: $title)
                Picker("Category", selection: $category) {
                    ForEach(allCategories, id: \.self) { Text($0).tag($0) }
                }
                Stepper("Planned pomodoros: \(estimate)", value: $estimate, in: 1...40)
                Toggle("Spans multiple days", isOn: $multiDay)
                DatePicker(multiDay ? "Starts" : "Day", selection: $start, displayedComponents: .date)
                if multiDay {
                    DatePicker("Ends", selection: $end, in: start..., displayedComponents: .date)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes (append-only)").font(.caption).foregroundStyle(.secondary)
                    if !original.orderedNoteEntries.isEmpty {
                        ForEach(original.orderedNoteEntries.suffix(5)) { entry in
                            Text("[\(entry.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))] \(entry.text)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextEditor(text: $newNote)
                        .frame(minHeight: 60)
                    Text("New text is appended; earlier notes are kept.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 480)
    }

    private var allCategories: [String] {
        var cats = store.settings.categories
        if !cats.contains(category) { cats.append(category) }
        return cats.isEmpty ? categories : cats
    }

    private func save() {
        var t = original
        t.title = title.trimmingCharacters(in: .whitespaces)
        t.category = category
        t.estimatedPomodoros = estimate
        t.appendNote(newNote)
        t.isPlanned = true
        let cal = Calendar.current
        let s = cal.startOfDay(for: start)
        let e = cal.startOfDay(for: multiDay ? max(end, start) : start)
        t.plannedFor = s
        t.plannedUntil = (s == e) ? nil : e
        onSave(t)
    }
}
