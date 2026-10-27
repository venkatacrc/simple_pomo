import Foundation
import SwiftUI

/// Single source of truth. Holds tasks, sessions and settings.
/// Persists to `~/Library/Application Support/SimplePomo/store.json`.
@MainActor
final class DataStore: ObservableObject {
    @Published var tasks: [PomoTask] = []
    @Published var sessions: [PomoSession] = []
    @Published var settings: AppSettings = AppSettings()
    @Published var activeTaskId: UUID?

    private let fileURL: URL
    private var saveDebounce: DispatchWorkItem?

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let fm = FileManager.default
            let appSupport = (try? fm.url(for: .applicationSupportDirectory,
                                          in: .userDomainMask,
                                          appropriateFor: nil,
                                          create: true))
                ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            let dir = appSupport.appendingPathComponent("SimplePomo", isDirectory: true)
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            self.fileURL = dir.appendingPathComponent("store.json")
        }
        load()
    }

    // MARK: - Load / Save

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let store = try decoder.decode(StoreData.self, from: data)
            self.tasks = store.tasks.map { task in
                var t = task
                t.migrateLegacyNotesIfNeeded()
                return t
            }
            self.sessions = store.sessions
            self.settings = store.settings
        } catch {
            NSLog("SimplePomo: failed to load store: \(error)")
            // Move the unreadable file aside so the next autosave can't overwrite it.
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = fileURL.deletingLastPathComponent()
                .appendingPathComponent("store.unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
        }
    }

    func saveNow() {
        let payload = StoreData(tasks: tasks, sessions: sessions, settings: settings)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("SimplePomo: failed to save store: \(error)")
        }
    }

    /// Debounced save to avoid hammering disk during rapid edits.
    func save() {
        saveDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.saveNow() }
        }
        saveDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // MARK: - Tasks

    func addTask(_ task: PomoTask) {
        tasks.append(task)
        save()
    }

    func updateTask(_ task: PomoTask) {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx] = task
            save()
        }
    }

    func deleteTask(_ task: PomoTask) {
        tasks.removeAll { $0.id == task.id }
        if activeTaskId == task.id { activeTaskId = nil }
        save()
    }

    func toggleCompleted(_ task: PomoTask) {
        var t = task
        t.isCompleted.toggle()
        updateTask(t)
    }

    func incrementCompleted(taskId: UUID) {
        if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[idx].completedPomodoros += 1
            if tasks[idx].completedPomodoros >= tasks[idx].estimatedPomodoros,
               tasks[idx].estimatedPomodoros > 0 {
                // Don't auto-complete; just count. Users can mark done manually.
            }
            save()
        }
    }

    var activeTask: PomoTask? {
        guard let id = activeTaskId else { return nil }
        return tasks.first(where: { $0.id == id })
    }

    /// Frictionless "what am I working on" capture: reuses an existing open
    /// task with a matching title + category if one exists (so retyping the
    /// same thing later the same day doesn't spam duplicates), otherwise
    /// creates a lightweight ad-hoc task and makes it active immediately —
    /// no sheet, no required fields. This is the fast path used by the
    /// quick-capture field on the Focus screen.
    func setActiveTask(title: String, category: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let idx = tasks.firstIndex(where: {
            !$0.isCompleted && !$0.isArchived &&
            $0.title.caseInsensitiveCompare(trimmed) == .orderedSame &&
            $0.category == category
        }) {
            activeTaskId = tasks[idx].id
            save()
            return
        }

        let task = PomoTask(title: trimmed, category: category, estimatedPomodoros: 1)
        tasks.append(task)
        activeTaskId = task.id
        save()
    }

    /// Append a dated note to the active task. Never overwrites prior notes.
    @discardableResult
    func appendActiveTaskNote(_ text: String) -> Bool {
        guard let id = activeTaskId,
              let idx = tasks.firstIndex(where: { $0.id == id }) else { return false }
        let before = tasks[idx].noteEntries.count
        tasks[idx].appendNote(text)
        guard tasks[idx].noteEntries.count > before else { return false }
        save()
        return true
    }

    /// Append a dated note to any task by id.
    func appendNote(_ text: String, toTaskId id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].appendNote(text)
        save()
    }

    func planTask(_ task: PomoTask, from start: Date, until end: Date? = nil) {
        var t = task
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: start)
        let endDay = cal.startOfDay(for: end ?? start)
        t.isPlanned = true
        t.plannedFor = min(startDay, endDay)
        t.plannedUntil = max(startDay, endDay)
        if t.plannedFor == t.plannedUntil {
            t.plannedUntil = nil  // single-day stays compact in storage
        }
        if let idx = tasks.firstIndex(where: { $0.id == t.id }) {
            tasks[idx] = t
        } else {
            tasks.append(t)
        }
        save()
    }

    /// Convenience for a single calendar day.
    func planTask(_ task: PomoTask, for day: Date) {
        planTask(task, from: day, until: day)
    }

    func unplanTask(_ task: PomoTask) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].isPlanned = false
        tasks[idx].plannedFor = nil
        tasks[idx].plannedUntil = nil
        save()
    }

    /// Tasks whose plan spans this calendar day.
    func plannedTasks(on day: Date) -> [PomoTask] {
        tasks.filter { $0.isPlanned && !$0.isArchived && $0.isPlanned(on: day) }
            .sorted { ($0.plannedFor ?? .distantPast) < ($1.plannedFor ?? .distantPast) }
    }

    /// Tasks whose plan overlaps the given range (e.g. a week).
    func plannedTasks(in range: ClosedRange<Date>) -> [PomoTask] {
        let cal = Calendar.current
        let rangeStart = cal.startOfDay(for: range.lowerBound)
        let rangeEnd = cal.startOfDay(for: range.upperBound)
        return tasks.filter { task in
            guard task.isPlanned, !task.isArchived, let span = task.plannedDayRange else { return false }
            return span.lowerBound <= rangeEnd && span.upperBound >= rangeStart
        }
        .sorted {
            ($0.plannedFor ?? .distantPast, $0.title) < ($1.plannedFor ?? .distantPast, $1.title)
        }
    }

    /// Focus minutes logged for a task (by id or matching title) in a date range.
    func focusMinutes(for task: PomoTask, in range: ClosedRange<Date>) -> Double {
        sessions
            .filter {
                $0.phase == .focus &&
                $0.startedAt >= range.lowerBound && $0.startedAt <= range.upperBound &&
                ($0.taskId == task.id ||
                 $0.taskTitle.caseInsensitiveCompare(task.title) == .orderedSame)
            }
            .reduce(0.0) { $0 + $1.durationMinutes }
    }

    func focusSessionCount(for task: PomoTask, in range: ClosedRange<Date>) -> Int {
        sessions.filter {
            $0.phase == .focus &&
            $0.startedAt >= range.lowerBound && $0.startedAt <= range.upperBound &&
            ($0.taskId == task.id ||
             $0.taskTitle.caseInsensitiveCompare(task.title) == .orderedSame)
        }.count
    }

    // MARK: - Sessions

    func recordSession(_ session: PomoSession) {
        sessions.append(session)
        save()
    }

    /// Adds a new entry (used by the manual "log past work" sheet) or
    /// updates an existing one in place, keyed by `id`. Lets people add
    /// what they worked on at the end of the day, or correct/backfill
    /// entries later in the week.
    func upsertSession(_ session: PomoSession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        save()
    }

    func deleteSession(_ session: PomoSession) {
        sessions.removeAll { $0.id == session.id }
        save()
    }

    // MARK: - Settings

    func updateSettings(_ newSettings: AppSettings) {
        self.settings = newSettings
        save()
    }
}
