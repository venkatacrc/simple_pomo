import SwiftUI

struct TaskListView: View {
    @EnvironmentObject var store: DataStore
    @State private var showingAdd = false
    @State private var editingTask: PomoTask?
    @State private var filterCategory: String = "All"
    @State private var showCompleted: Bool = false

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
    }

    private var categories: [String] {
        var seen = Set<String>()
        var result: [String] = ["All"]
        for t in store.tasks where !seen.contains(t.category) && !t.category.isEmpty {
            seen.insert(t.category)
            result.append(t.category)
        }
        return result
    }

    private var filteredTasks: [PomoTask] {
        store.tasks
            .filter { !$0.isArchived }
            .filter { showCompleted || !$0.isCompleted }
            .filter { filterCategory == "All" || $0.category == filterCategory }
            .sorted { ($0.isCompleted ? 1 : 0, $0.createdAt) < ($1.isCompleted ? 1 : 0, $1.createdAt) }
    }

    private var toolbar: some View {
        HStack {
            Text("Tasks")
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
            Text("No tasks yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Add a task to estimate and track your pomodoros.")
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
    let task: PomoTask
    let isActive: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void
    let onEdit: () -> Void
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
                Text(task.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .strikethrough(task.isCompleted)
                HStack(spacing: 8) {
                    CategoryBadge(name: task.category)
                    if !task.notes.isEmpty {
                        Text(task.notes)
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

            Button(action: onSelect) {
                Image(systemName: isActive ? "target" : "play.circle")
                    .font(.title3)
                    .foregroundStyle(isActive ? .yellow : .white)
            }
            .buttonStyle(.plain)
            .help(isActive ? "Active task" : "Set as active")

            Menu {
                Button("Edit", action: onEdit)
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
            Button("Edit", action: onEdit)
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
    @State private var category: String
    @State private var estimated: Int
    @State private var notes: String
    @State private var newCategory: String = ""

    init(task: PomoTask?, onSave: @escaping (PomoTask) -> Void) {
        self.original = task
        self.onSave = onSave
        _title = State(initialValue: task?.title ?? "")
        _category = State(initialValue: task?.category ?? "Work")
        _estimated = State(initialValue: task?.estimatedPomodoros ?? 1)
        _notes = State(initialValue: task?.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(original == nil ? "New Task" : "Edit Task")
                .font(.title3.weight(.semibold))

            Form {
                TextField("Title", text: $title)
                Picker("Category", selection: $category) {
                    ForEach(allCategories, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    TextField("New category…", text: $newCategory)
                    Button("Add") {
                        let trimmed = newCategory.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        if !store.settings.categories.contains(trimmed) {
                            var s = store.settings
                            s.categories.append(trimmed)
                            store.updateSettings(s)
                        }
                        category = trimmed
                        newCategory = ""
                    }
                    .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Stepper("Estimated pomodoros: \(estimated)", value: $estimated, in: 1...20)
                VStack(alignment: .leading) {
                    Text("Notes").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                        .border(Color.secondary.opacity(0.2))
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
        .frame(minWidth: 460, minHeight: 420)
    }

    private var allCategories: [String] {
        var cats = store.settings.categories
        if let cat = original?.category, !cats.contains(cat) { cats.append(cat) }
        return cats.isEmpty ? ["Work"] : cats
    }

    private func save() {
        var t = original ?? PomoTask(title: title, category: category, estimatedPomodoros: estimated)
        t.title = title.trimmingCharacters(in: .whitespaces)
        t.category = category
        t.estimatedPomodoros = estimated
        t.notes = notes
        onSave(t)
        dismiss()
    }
}
