import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var timer: PomodoroTimer

    var body: some View {
        TabView {
            timerSettings.tabItem { Label("Timer", systemImage: "timer") }
            categorySettings.tabItem { Label("Categories", systemImage: "tag") }
            dataSettings.tabItem { Label("Data", systemImage: "externaldrive") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 460, minHeight: 360)
    }

    private var settingsBinding: Binding<AppSettings> {
        Binding(
            get: { store.settings },
            set: { newValue in
                store.updateSettings(newValue)
                timer.refreshForSettingsChange()
            }
        )
    }

    // MARK: - Timer

    private var timerSettings: some View {
        Form {
            Section("Durations (minutes)") {
                Stepper("Pomodoro: \(store.settings.focusMinutes)",
                        value: settingsBinding.focusMinutes, in: 1...90)
                Stepper("Short break: \(store.settings.shortBreakMinutes)",
                        value: settingsBinding.shortBreakMinutes, in: 1...30)
                Stepper("Long break: \(store.settings.longBreakMinutes)",
                        value: settingsBinding.longBreakMinutes, in: 1...60)
                Stepper("Long break every: \(store.settings.longBreakEvery) pomodoros",
                        value: settingsBinding.longBreakEvery, in: 2...10)
            }
            Section("Auto-start") {
                Toggle("Auto-start breaks", isOn: settingsBinding.autoStartBreaks)
                Toggle("Auto-start pomodoros", isOn: settingsBinding.autoStartPomodoros)
            }
            Section("Sound") {
                Toggle("Play sound on phase end", isOn: settingsBinding.playSound)
                Picker("Sound", selection: settingsBinding.soundName) {
                    ForEach(["Glass", "Ping", "Tink", "Pop", "Hero", "Funk", "Submarine"], id: \.self) { Text($0).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Categories

    @State private var newCategory: String = ""

    private var categorySettings: some View {
        Form {
            Section("Existing categories") {
                if store.settings.categories.isEmpty {
                    Text("No categories yet.").foregroundStyle(.secondary)
                }
                ForEach(store.settings.categories, id: \.self) { cat in
                    HStack {
                        CategoryBadge(name: cat)
                        Text(cat)
                        Spacer()
                        Button(role: .destructive) {
                            var s = store.settings
                            s.categories.removeAll { $0 == cat }
                            store.updateSettings(s)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                }
            }
            Section("Add category") {
                HStack {
                    TextField("Name", text: $newCategory)
                    Button("Add") {
                        let trimmed = newCategory.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        var s = store.settings
                        if !s.categories.contains(trimmed) {
                            s.categories.append(trimmed)
                            store.updateSettings(s)
                        }
                        newCategory = ""
                    }
                    .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Data

    private var dataSettings: some View {
        Form {
            Section("Storage") {
                LabeledContent("Tasks", value: "\(store.tasks.count)")
                LabeledContent("Sessions", value: "\(store.sessions.count)")
                Button("Reveal data file in Finder") {
                    if let url = storeURL() {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
            Section("Reset") {
                Button("Clear all sessions", role: .destructive) {
                    store.sessions.removeAll()
                    store.saveNow()
                }
                Button("Clear all tasks", role: .destructive) {
                    store.tasks.removeAll()
                    store.activeTaskId = nil
                    store.saveNow()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func storeURL() -> URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ) else { return nil }
        return dir.appendingPathComponent("SimplePomo/store.json")
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 14) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Simple Pomo")
                .font(.title.weight(.bold))
            Text("A native macOS pomodoro timer with tasks, categories, and reports.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Built with SwiftUI + Swift Charts")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
