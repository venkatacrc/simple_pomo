import Foundation
import SwiftUI
import AppKit
import UserNotifications

@MainActor
final class PomodoroTimer: ObservableObject {
    @Published private(set) var phase: Phase = .focus
    @Published private(set) var remaining: Int = 25 * 60
    @Published private(set) var totalForPhase: Int = 25 * 60
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var completedFocusInCycle: Int = 0

    private weak var store: DataStore?
    private var ticker: Timer?
    private var phaseStartedAt: Date?

    init(store: DataStore) {
        self.store = store
        configurePhase(.focus, reset: true)
        requestNotificationPermissionIfNeeded()
    }

    // MARK: - Phase control

    func configurePhase(_ newPhase: Phase, reset: Bool) {
        phase = newPhase
        let mins = store?.settings.minutes(for: newPhase) ?? 25
        totalForPhase = mins * 60
        if reset { remaining = totalForPhase }
        phaseStartedAt = nil
    }

    func switchPhase(_ newPhase: Phase) {
        pause()
        configurePhase(newPhase, reset: true)
    }

    func start() {
        guard !isRunning else { return }
        if phaseStartedAt == nil { phaseStartedAt = Date() }
        isRunning = true
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause() {
        isRunning = false
        ticker?.invalidate()
        ticker = nil
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func reset() {
        pause()
        configurePhase(phase, reset: true)
    }

    /// Skip the current phase. Focus phases save a partial session if at least one minute elapsed.
    func skip() {
        let started = phaseStartedAt
        let elapsed = totalForPhase - remaining
        pause()
        if phase == .focus, let start = started, elapsed >= 60 {
            recordSession(start: start, end: Date())
        }
        advanceToNextPhase(naturalCompletion: false)
    }

    // MARK: - Timer tick

    private func tick() {
        guard isRunning else { return }
        if remaining > 0 {
            remaining -= 1
        } else {
            completePhase()
        }
    }

    private func completePhase() {
        let started = phaseStartedAt ?? Date().addingTimeInterval(-Double(totalForPhase))
        let ended = Date()
        pause()
        if phase == .focus {
            recordSession(start: started, end: ended)
            completedFocusInCycle += 1
            if let taskId = store?.activeTaskId {
                store?.incrementCompleted(taskId: taskId)
            }
        }
        notifyPhaseComplete()
        advanceToNextPhase(naturalCompletion: true)
    }

    private func advanceToNextPhase(naturalCompletion: Bool) {
        let settings = store?.settings ?? AppSettings()
        let next: Phase
        switch phase {
        case .focus:
            if completedFocusInCycle > 0,
               completedFocusInCycle % settings.longBreakEvery == 0 {
                next = .longBreak
            } else {
                next = .shortBreak
            }
        case .shortBreak, .longBreak:
            next = .focus
        }
        configurePhase(next, reset: true)

        guard naturalCompletion else { return }
        let shouldAutoStart: Bool
        switch next {
        case .focus: shouldAutoStart = settings.autoStartPomodoros
        case .shortBreak, .longBreak: shouldAutoStart = settings.autoStartBreaks
        }
        if shouldAutoStart { start() }
    }

    // MARK: - Session recording

    private func recordSession(start: Date, end: Date) {
        guard let store else { return }
        let task = store.activeTask
        let session = PomoSession(
            taskId: task?.id,
            taskTitle: task?.title ?? "Focus",
            category: task?.category ?? "Uncategorized",
            phase: .focus,
            startedAt: start,
            endedAt: end
        )
        store.recordSession(session)
    }

    // MARK: - Notification / sound

    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyPhaseComplete() {
        if store?.settings.playSound ?? true {
            let name = store?.settings.soundName ?? "Glass"
            NSSound(named: name)?.play()
        }
        let content = UNMutableNotificationContent()
        switch phase {
        case .focus:
            content.title = "Pomodoro complete"
            content.body = "Time for a break."
        case .shortBreak:
            content.title = "Break over"
            content.body = "Back to focus."
        case .longBreak:
            content.title = "Long break over"
            content.body = "Ready for another round?"
        }
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content,
                                        trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    // MARK: - Derived display helpers

    var progress: Double {
        guard totalForPhase > 0 else { return 0 }
        return 1.0 - Double(remaining) / Double(totalForPhase)
    }

    var displayTime: String {
        let m = remaining / 60
        let s = remaining % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// Called when user changes durations in settings — keeps the displayed time fresh.
    func refreshForSettingsChange() {
        if !isRunning {
            configurePhase(phase, reset: true)
        }
    }
}
