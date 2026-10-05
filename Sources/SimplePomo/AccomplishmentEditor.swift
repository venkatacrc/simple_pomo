import SwiftUI

// MARK: - Single entry editor

/// Add or edit one work-log entry. Used for the "+" quick-add button in
/// Reports → Accomplishments, and for editing/deleting any existing entry —
/// so you can jot down what you worked on at the end of the day, or correct
/// something later in the week.
struct SessionEditorSheet: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let original: PomoSession
    let isNew: Bool
    let onSave: (PomoSession) -> Void
    let onDelete: (() -> Void)?

    @State private var title: String
    @State private var category: String
    @State private var date: Date
    @State private var minutes: Int

    init(
        session: PomoSession,
        isNew: Bool,
        onSave: @escaping (PomoSession) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.original = session
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: session.taskTitle)
        _category = State(initialValue: session.category)
        _date = State(initialValue: session.startedAt)
        _minutes = State(initialValue: max(5, Int(session.durationMinutes.rounded())))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Log past work" : "Edit entry")
                .font(.title3.weight(.semibold))

            Form {
                TextField("What did you work on?", text: $title)
                Picker("Category", selection: $category) {
                    ForEach(categoryOptions, id: \.self) { Text($0).tag($0) }
                }
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                Stepper("Duration: \(minutes) min (~\(pomodoroCountLabel) 🍅)",
                        value: $minutes, in: 5...480, step: 5)
            }
            .formStyle(.grouped)

            HStack {
                if !isNew, let onDelete {
                    Button("Delete", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(isNew ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 340)
    }

    private var categoryOptions: [String] {
        var cats = store.settings.categories
        if !category.isEmpty, !cats.contains(category) { cats.append(category) }
        if !cats.contains("Quick") { cats.append("Quick") }
        return cats
    }

    private var pomodoroCountLabel: String {
        let focusLen = max(store.settings.focusMinutes, 1)
        return String(format: "%.1f", Double(minutes) / Double(focusLen))
    }

    private func save() {
        var updated = original
        updated.taskTitle = title.trimmingCharacters(in: .whitespaces)
        updated.category = category
        updated.startedAt = date
        updated.endedAt = date.addingTimeInterval(TimeInterval(minutes * 60))
        updated.isManual = true
        onSave(updated)
        dismiss()
    }
}

// MARK: - Group breakdown (when a day has multiple sessions for one task)

/// Shown when an "Accomplishments" entry is the sum of more than one
/// session on the same day — lets you edit or delete each one individually,
/// or add another chunk of time for the same item.
struct SessionGroupSheet: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let date: Date
    let title: String
    let category: String
    let onEdit: (PomoSession) -> Void
    let onAddMore: () -> Void

    private var matchingSessions: [PomoSession] {
        let cal = Calendar.current
        return store.sessions
            .filter {
                cal.isDate($0.startedAt, inSameDayAs: date) &&
                $0.taskTitle == title && $0.category == category
            }
            .sorted { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CategoryBadge(name: category)
            }

            List {
                ForEach(matchingSessions) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.startedAt, format: .dateTime.hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Text(formatDuration(session.durationMinutes))
                                if session.isManual {
                                    Text("Manual")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        Button("Edit") { onEdit(session) }
                        Button(role: .destructive) {
                            store.deleteSession(session)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(minHeight: 160)

            HStack {
                Button(action: onAddMore) {
                    Label("Add more time", systemImage: "plus.circle")
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 380)
    }

    private func formatDuration(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total)m" }
        let h = total / 60
        let m = total % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
