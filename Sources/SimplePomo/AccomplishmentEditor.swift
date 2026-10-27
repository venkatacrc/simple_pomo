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
    @State private var newNote: String = ""

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
        _newNote = State(initialValue: "")
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

                notesSection
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
        .frame(minWidth: 460, minHeight: 480)
    }

    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Session notes (append-only)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let task = linkedTask, !task.orderedNoteEntries.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(task.orderedNoteEntries) { entry in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(entry.text)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxHeight: 100)
            } else if linkedTask == nil {
                Text("Notes are saved on the matching task after you save this entry.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: $newNote)
                .frame(minHeight: 60)
                .border(Color.secondary.opacity(0.2))
            Text("New text is appended with a timestamp; earlier notes stay intact.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Prefer taskId, then fall back to title match.
    private var linkedTask: PomoTask? {
        if let id = original.taskId, let task = store.tasks.first(where: { $0.id == id }) {
            return task
        }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return store.tasks.first {
            $0.title.caseInsensitiveCompare(trimmed.isEmpty ? original.taskTitle : trimmed) == .orderedSame
        }
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

        let noteText = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !noteText.isEmpty {
            if let id = updated.taskId ?? linkedTask?.id {
                store.appendNote(noteText, toTaskId: id)
            } else if let match = store.tasks.first(where: {
                $0.title.caseInsensitiveCompare(updated.taskTitle) == .orderedSame
            }) {
                store.appendNote(noteText, toTaskId: match.id)
            } else {
                // Create a lightweight task so notes have a home.
                var task = PomoTask(title: updated.taskTitle, category: updated.category)
                task.appendNote(noteText)
                store.addTask(task)
                updated.taskId = task.id
                store.upsertSession(updated)
            }
        }
        dismiss()
    }
}

// MARK: - Notes-only sheet (from Accomplishments)

/// Focused append-only notes editor opened from an Accomplishments row.
struct TaskNotesSheet: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let taskTitle: String
    let category: String
    let taskId: UUID?

    @State private var newNote: String = ""

    private var task: PomoTask? {
        if let taskId, let t = store.tasks.first(where: { $0.id == taskId }) { return t }
        return store.tasks.first {
            $0.title.caseInsensitiveCompare(taskTitle) == .orderedSame &&
            $0.category == category
        } ?? store.tasks.first {
            $0.title.caseInsensitiveCompare(taskTitle) == .orderedSame
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Notes")
                    .font(.title3.weight(.semibold))
                Text(taskTitle)
                    .foregroundStyle(.secondary)
            }

            if let task, !task.orderedNoteEntries.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(task.orderedNoteEntries) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(entry.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.secondary.opacity(0.08))
                            )
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 220)
            } else {
                Text("No notes yet for this task.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Add a note").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $newNote)
                    .frame(minHeight: 70)
                    .border(Color.secondary.opacity(0.2))
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                Button("Add note") { appendAndKeepOpen() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 400)
    }

    private func appendAndKeepOpen() {
        let trimmed = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let id = task?.id {
            store.appendNote(trimmed, toTaskId: id)
        } else {
            var t = PomoTask(title: taskTitle, category: category)
            t.appendNote(trimmed)
            store.addTask(t)
        }
        newNote = ""
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
