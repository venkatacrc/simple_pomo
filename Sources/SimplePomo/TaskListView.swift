import SwiftUI

struct TaskListView: View {
    @EnvironmentObject var store: DataStore
    @State private var showingAdd = false
    @State private var editingTask: PomoTask?
    @State private var filterCategory: String = "All"
    @State private var showCompleted: Bool = false
    @State private var notesTask: PomoTask?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.2)
            list
        }
        .sheet(isPresented: $showingAdd) {
            TaskEditor(task: nil) { task in
                store.addTask(task)
            }
            .environmentObject(store)
        }
        .sheet(item: $editingTask) { task in
            TaskEditor(task: task) { updated in
                store.updateTask(updated)
            }
            .environmentObject(store)
        }
        .sheet(item: $notesTask) { task in
            TaskNotesSheet(taskTitle: task.title, category: task.category, taskId: task.id)
                .environmentObject(store)
        }
        .onChange(of: store.settings.activeArea) { _, _ in
            filterCategory = "All"
        }
    }

    private var area: LifeArea { store.settings.activeArea }

    private var categories: [String] {
        var seen = Set<String>()
        var result: [String] = ["All"]
        for name in store.settings.categories(for: area) where seen.insert(name).inserted {
            result.append(name)
        }
        for t in store.tasks where t.area == area && !t.category.isEmpty && seen.insert(t.category).inserted {
            result.append(t.category)
        }
        return result
    }

    private var filteredTasks: [PomoTask] {
        store.tasks
            .filter { !$0.isArchived && $0.area == area }
            .filter { showCompleted || !$0.isCompleted }
            .filter { filterCategory == "All" || $0.category == filterCategory }
            .sorted { ($0.isCompleted ? 1 : 0, $0.createdAt) < ($1.isCompleted ? 1 : 0, $1.createdAt) }
    }

    private var toolbar: some View {
        HStack {
            Text("\(store.settings.activeArea.label) tasks")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            Picker("Category", selection: $filterCategory) {
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            }
            .frame(maxWidth: 180)
            Toggle("Show completed", isOn: $showCompleted)
                .toggleStyle(.switch)
                .foregroundStyle(.white)
            Button {
                showingAdd = true
            } label: {
                Label("Add Task", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if filteredTasks.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredTasks) { task in
                        TaskRow(task: task,
                                isActive: store.activeTaskId == task.id,
                                onSelect: { store.activeTaskId = store.activeTaskId == task.id ? nil : task.id },
                                onToggle: { store.toggleCompleted(task) },
                                onEdit: { editingTask = task },
                                onNotes: { notesTask = task },
                                onDelete: { store.deleteTask(task) })
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 880)
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.4))
            Text("No \(store.settings.activeArea.label.lowercased()) tasks")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Tasks you add here stay in \(store.settings.activeArea.label). Switch the header to see the other list.")
                .foregroundStyle(.white.opacity(0.65))
            Button("Add your first task") { showingAdd = true }
                .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Task row

private struct TaskRow: View {
    @EnvironmentObject var store: DataStore
    let task: PomoTask
    let isActive: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onNotes: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isCompleted ? .green : .white.opacity(0.55))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .strikethrough(task.isCompleted)
                    if task.isPlanned {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundStyle(.cyan)
                            .help({
                                guard let range = task.plannedDayRange else { return "Planned" }
                                let fmt = Date.FormatStyle().month(.abbreviated).day()
                                if Calendar.current.isDate(range.lowerBound, inSameDayAs: range.upperBound) {
                                    return "Planned for \(range.lowerBound.formatted(fmt))"
                                }
                                return "Planned \(range.lowerBound.formatted(fmt))–\(range.upperBound.formatted(fmt))"
                            }())
                    }
                }
                HStack(spacing: 8) {
                    CategoryBadge(name: task.category)
                    if !task.notesLog.isEmpty {
                        Text(task.notesLog)
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.6))
                            .font(.caption)
                    }
                }
            }
            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(task.completedPomodoros)/\(task.estimatedPomodoros)")
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.1)))

            Button(action: onNotes) {
                Image(systemName: "note.text")
                    .font(.title3)
                    .foregroundStyle(task.orderedNoteEntries.isEmpty ? .white.opacity(0.55) : .cyan)
            }
            .buttonStyle(.plain)
            .help("Add or read notes without making this the active task")

            Button(action: onSelect) {
                Image(systemName: isActive ? "target" : "play.circle")
                    .font(.title3)
                    .foregroundStyle(isActive ? .yellow : .white)
            }
            .buttonStyle(.plain)
            .help(isActive ? "Active task" : "Set as active")

            Menu {
                Button("Notes", action: onNotes)
                Button("Edit", action: onEdit)
                if task.isPlanned {
                    Button("Remove from plan") { store.unplanTask(task) }
                } else {
                    Button("Add to today's plan") { store.planTask(task, for: Date()) }
                }
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.white.opacity(0.7))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? Color.white.opacity(0.18) : Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isActive ? Color.yellow.opacity(0.6) : Color.clear, lineWidth: 1)
        )
        .contextMenu {
            Button("Notes", action: onNotes)
            Button("Edit", action: onEdit)
            if task.isPlanned {
                Button("Remove from plan") { store.unplanTask(task) }
            } else {
                Button("Add to today's plan") { store.planTask(task, for: Date()) }
            }
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Editor

private struct TaskEditor: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    let original: PomoTask?
    let onSave: (PomoTask) -> Void

    @State private var title: String
    @State private var area: LifeArea
    @State private var category: String
    @State private var estimated: Int
    @State private var newNote: String = ""
    @State private var newCategory: String = ""

    init(task: PomoTask?, onSave: @escaping (PomoTask) -> Void) {
        self.original = task
        self.onSave = onSave
        _title = State(initialValue: task?.title ?? "")
        let startingArea = task?.area ?? .work
        _area = State(initialValue: startingArea)
        _category = State(initialValue: task?.category ?? "Work")
        _estimated = State(initialValue: task?.estimatedPomodoros ?? 1)
        _newNote = State(initialValue: "")
        _newCategory = State(initialValue: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(original == nil ? "New Task" : "Edit Task")
                .font(.title3.weight(.semibold))

            Form {
                TextField("Title", text: $title)
                Picker("Area", selection: $area) {
                    ForEach(LifeArea.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: area) { _, newArea in
                    let options = store.settings.categories(for: newArea)
                    if !options.contains(category) {
                        category = options.first ?? newArea.label
                    }
                }
                Picker("Category", selection: $category) {
                    ForEach(allCategories, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    TextField("New \(area.label.lowercased()) category…", text: $newCategory)
                    Button("Add") {
                        let trimmed = newCategory.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        var s = store.settings
                        s.addCategory(trimmed, to: area)
                        store.updateSettings(s)
                        category = trimmed
                        newCategory = ""
                    }
                    .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Stepper("Estimated pomodoros: \(estimated)", value: $estimated, in: 1...20)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes (append-only)").font(.caption).foregroundStyle(.secondary)
                    if let original, !original.orderedNoteEntries.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(original.orderedNoteEntries) { entry in
                                    Text("[\(entry.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))] \(entry.text)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(maxHeight: 90)
                    } else if let original, !original.notes.isEmpty {
                        Text(original.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextEditor(text: $newNote)
                        .frame(minHeight: 60)
                        .border(Color.secondary.opacity(0.2))
                    Text("New text is appended with a timestamp; prior notes are kept.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(original == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 500)
        .onAppear {
            if original == nil {
                area = store.settings.activeArea
                category = store.settings.categories(for: area).first ?? area.label
            }
        }
    }

    private var allCategories: [String] {
        var cats = store.settings.categories(for: area)
        if let cat = original?.category, original?.area == area, !cats.contains(cat) { cats.append(cat) }
        if !cats.contains(category) { cats.append(category) }
        return cats.isEmpty ? [area.label] : cats
    }

    private func save() {
        var t = original ?? PomoTask(title: title, category: category, estimatedPomodoros: estimated)
        t.title = title.trimmingCharacters(in: .whitespaces)
        t.area = area
        t.category = category
        t.estimatedPomodoros = estimated
        t.appendNote(newNote)
        onSave(t)
        dismiss()
    }
}
