import SwiftUI

struct FocusView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var timer: PomodoroTimer
    @State private var draftText: String = ""
    @State private var draftCategory: String = ""
    @FocusState private var captureFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                presetPicker
                phaseTabs
                HStack(alignment: .top, spacing: 24) {
                    SeasonalClockView(diameter: 260)
                        .frame(maxWidth: .infinity)
                    timerCard
                        .frame(maxWidth: .infinity)
                }
                activeTaskCard
                quickTaskList
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Preset picker

    private var presetPicker: some View {
        let active = store.settings.activePreset
        return HStack(spacing: 8) {
            ForEach(TimerPreset.allCases) { preset in
                let isActive = active == preset
                Button {
                    applyPreset(preset)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: preset.symbol)
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(preset.title)
                                .font(.caption.weight(.semibold))
                            Text(preset.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(
                            isActive ? Color.white.opacity(0.24) : Color.white.opacity(0.06)
                        )
                    )
                    .overlay(
                        Capsule().stroke(isActive ? Color.white.opacity(0.5) : .clear, lineWidth: 1)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help("\(preset.focusMinutes)m focus / \(preset.shortBreakMinutes)m break / \(preset.longBreakMinutes)m long break")
            }
        }
    }

    private func applyPreset(_ preset: TimerPreset) {
        var settings = store.settings
        settings.apply(preset)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            store.updateSettings(settings)
            timer.refreshForSettingsChange()
        }
    }

    // MARK: - Phase tabs

    private var phaseTabs: some View {
        HStack(spacing: 8) {
            ForEach(Phase.allCases) { phase in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        timer.switchPhase(phase)
                    }
                } label: {
                    Text(phase.title)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(
                                phase == timer.phase
                                    ? Color.white.opacity(0.22)
                                    : Color.white.opacity(0.06)
                            )
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Timer card

    private var timerCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 14)

                Circle()
                    .trim(from: 0, to: max(0.001, timer.progress))
                    .stroke(
                        Color.white.opacity(0.95),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: timer.progress)

                VStack(spacing: 6) {
                    Text(timer.displayTime)
                        .font(.system(size: 76, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(timer.phase.title.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: 280, height: 280)

            controls
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                timer.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(GlassCircleButton())

            Button {
                timer.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    Text(timer.isRunning ? "PAUSE" : "START")
                        .font(.headline.weight(.heavy))
                        .tracking(3)
                }
                .frame(minWidth: 180)
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
            }
            .buttonStyle(PrimaryButton(tint: timer.phase.tint))

            Button {
                timer.skip()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(GlassCircleButton())
        }
    }

    // MARK: - Quick capture ("what are you working on?")

    /// A frictionless, always-visible text field: type what you're doing
    /// right now and hit Return. It becomes the active task for this session
    /// (created on the fly — no sheet, no required estimate) and every
    /// focus session you log afterwards carries that description, category,
    /// and timestamp straight into Reports → Accomplishments.
    private var activeTaskCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            quickCaptureField
            if let task = store.activeTask {
                Divider().opacity(0.14)
                HStack(spacing: 10) {
                    Image(systemName: "target")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("\(task.completedPomodoros)/\(task.estimatedPomodoros) pomodoros logged")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    Button("Clear") {
                        store.activeTaskId = nil
                        draftText = ""
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .onAppear {
            draftText = store.activeTask?.title ?? ""
            draftCategory = store.activeTask?.category ?? store.settings.categories.first ?? "Quick"
        }
        .onChange(of: store.activeTaskId) { _, _ in
            draftText = store.activeTask?.title ?? ""
            if let cat = store.activeTask?.category { draftCategory = cat }
        }
        .onChange(of: timer.phase) { _, newPhase in
            // Prompt for fresh input when a new focus block begins and the
            // field is empty — but never steal focus if something's typed.
            if newPhase == .focus, draftText.trimmingCharacters(in: .whitespaces).isEmpty {
                captureFocused = true
            }
        }
    }

    private var quickCaptureField: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.line")
                .foregroundStyle(.white.opacity(0.65))
            TextField("What are you working on?", text: $draftText)
                .textFieldStyle(.plain)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .focused($captureFocused)
                .onSubmit(commitDraft)

            Menu {
                ForEach(allCategoryOptions, id: \.self) { cat in
                    Button(cat) { draftCategory = cat }
                }
            } label: {
                CategoryBadge(name: draftCategory.isEmpty ? "Quick" : draftCategory)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button(action: commitDraft) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(
                        draftText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? .white.opacity(0.3)
                            : .white
                    )
            }
            .buttonStyle(.plain)
            .disabled(draftText.trimmingCharacters(in: .whitespaces).isEmpty)
            .help("Set as active task (Return)")
        }
    }

    private var allCategoryOptions: [String] {
        var cats = store.settings.categories
        if !cats.contains("Quick") { cats.append("Quick") }
        return cats
    }

    private func commitDraft() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cat = draftCategory.isEmpty ? (store.settings.categories.first ?? "Quick") : draftCategory
        store.setActiveTask(title: trimmed, category: cat)
        draftCategory = cat
        captureFocused = false
    }

    // MARK: - Quick task list (today)

    private var quickTaskList: some View {
        let openTasks = store.tasks.filter { !$0.isArchived && !$0.isCompleted }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Up next")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(openTasks.count) open")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            if openTasks.isEmpty {
                Text("Add tasks in the Tasks tab to track them here.")
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 6) {
                    ForEach(openTasks.prefix(5)) { task in
                        QuickTaskRow(task: task)
                    }
                }
            }
        }
    }
}

// MARK: - Quick task row

private struct QuickTaskRow: View {
    @EnvironmentObject var store: DataStore
    let task: PomoTask

    var body: some View {
        let isActive = store.activeTaskId == task.id
        HStack(spacing: 12) {
            Button {
                store.toggleCompleted(task)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? .green : .white.opacity(0.6))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .foregroundStyle(.white)
                CategoryBadge(name: task.category)
            }
            Spacer()
            Text("\(task.completedPomodoros)/\(task.estimatedPomodoros)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))

            Button {
                store.activeTaskId = isActive ? nil : task.id
            } label: {
                Image(systemName: isActive ? "target" : "arrow.right.circle")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? Color.white.opacity(0.18) : Color.white.opacity(0.06))
        )
    }
}

// MARK: - Buttons

struct PrimaryButton: ButtonStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .background(
                Capsule().fill(Color.white)
            )
            .shadow(color: .black.opacity(0.2), radius: configuration.isPressed ? 2 : 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct GlassCircleButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                Circle().fill(Color.white.opacity(configuration.isPressed ? 0.28 : 0.15))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Category badge

struct CategoryBadge: View {
    let name: String
    var body: some View {
        Text(name.isEmpty ? "Uncategorized" : name)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color(for: name).opacity(0.35))
            )
            .overlay(
                Capsule().stroke(color(for: name).opacity(0.7), lineWidth: 0.5)
            )
            .foregroundStyle(.white)
    }

    private func color(for name: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.86, green: 0.31, blue: 0.31),
            Color(red: 0.27, green: 0.62, blue: 0.55),
            Color(red: 0.30, green: 0.47, blue: 0.74),
            Color(red: 0.83, green: 0.58, blue: 0.24),
            Color(red: 0.55, green: 0.36, blue: 0.74),
            Color(red: 0.30, green: 0.60, blue: 0.40)
        ]
        let h = abs(name.hashValue) % palette.count
        return palette[h]
    }
}
