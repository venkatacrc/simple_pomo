import Foundation
import SwiftUI

// MARK: - Phase

enum Phase: String, Codable, CaseIterable, Identifiable {
    case focus
    case shortBreak
    case longBreak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "Pomodoro"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }

    var tint: Color {
        switch self {
        case .focus: return Color(red: 0.86, green: 0.31, blue: 0.31)        // tomato
        case .shortBreak: return Color(red: 0.27, green: 0.62, blue: 0.55)   // teal
        case .longBreak: return Color(red: 0.30, green: 0.47, blue: 0.74)    // ocean
        }
    }

    var accentBackground: Color {
        switch self {
        case .focus: return Color(red: 0.74, green: 0.27, blue: 0.27)
        case .shortBreak: return Color(red: 0.23, green: 0.52, blue: 0.47)
        case .longBreak: return Color(red: 0.25, green: 0.40, blue: 0.62)
        }
    }
}

// MARK: - Task

struct PomoTask: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var title: String
    var category: String
    var estimatedPomodoros: Int = 1
    var completedPomodoros: Int = 0
    var notes: String = ""
    var isCompleted: Bool = false
    var isArchived: Bool = false
    var createdAt: Date = Date()
}

// MARK: - Session record

struct PomoSession: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var taskId: UUID?
    var taskTitle: String
    var category: String
    var phase: Phase
    var startedAt: Date
    var endedAt: Date
    /// True when this entry was typed in by hand (e.g. logging work from
    /// earlier in the day or week) rather than produced by a live timer run.
    var isManual: Bool = false

    var durationSeconds: Int {
        max(0, Int(endedAt.timeIntervalSince(startedAt)))
    }

    var durationMinutes: Double {
        Double(durationSeconds) / 60.0
    }

    /// Convenience constructor for manually-logged work: pick a date and a
    /// duration in minutes rather than start/end timestamps.
    static func manual(title: String, category: String, date: Date, minutes: Int) -> PomoSession {
        PomoSession(
            taskId: nil,
            taskTitle: title,
            category: category,
            phase: .focus,
            startedAt: date,
            endedAt: date.addingTimeInterval(TimeInterval(minutes * 60)),
            isManual: true
        )
    }
}

extension PomoSession {
    private enum CodingKeys: String, CodingKey {
        case id, taskId, taskTitle, category, phase, startedAt, endedAt, isManual
    }

    /// Store files written before `isManual` existed don't contain the key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        taskId = try c.decodeIfPresent(UUID.self, forKey: .taskId)
        taskTitle = try c.decode(String.self, forKey: .taskTitle)
        category = try c.decode(String.self, forKey: .category)
        phase = try c.decode(Phase.self, forKey: .phase)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decode(Date.self, forKey: .endedAt)
        isManual = try c.decodeIfPresent(Bool.self, forKey: .isManual) ?? false
    }
}

// MARK: - Timer presets

/// Named focus/break duration combos users can switch between with one tap.
enum TimerPreset: String, CaseIterable, Identifiable, Codable {
    case classic
    case extended
    case deepWork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .extended: return "Extended"
        case .deepWork: return "Deep Work"
        }
    }

    var subtitle: String {
        "\(focusMinutes) / \(shortBreakMinutes)"
    }

    var symbol: String {
        switch self {
        case .classic: return "timer"
        case .extended: return "hourglass"
        case .deepWork: return "brain.head.profile"
        }
    }

    var focusMinutes: Int {
        switch self {
        case .classic: return 25
        case .extended: return 50
        case .deepWork: return 90
        }
    }

    var shortBreakMinutes: Int {
        switch self {
        case .classic: return 5
        case .extended: return 10
        case .deepWork: return 20
        }
    }

    var longBreakMinutes: Int {
        switch self {
        case .classic: return 15
        case .extended: return 20
        case .deepWork: return 30
        }
    }
}

// MARK: - Settings

struct AppSettings: Codable, Equatable {
    var focusMinutes: Int = 25
    var shortBreakMinutes: Int = 5
    var longBreakMinutes: Int = 15
    var longBreakEvery: Int = 4
    var autoStartBreaks: Bool = true
    var autoStartPomodoros: Bool = false
    var playSound: Bool = true
    var soundName: String = "Glass"
    var categories: [String] = ["Work", "Study", "Personal", "Reading", "Side Project"]

    func minutes(for phase: Phase) -> Int {
        switch phase {
        case .focus: return focusMinutes
        case .shortBreak: return shortBreakMinutes
        case .longBreak: return longBreakMinutes
        }
    }

    /// The preset matching the current durations, if any (used to highlight
    /// the active choice in the UI). `nil` means the user has custom values.
    var activePreset: TimerPreset? {
        TimerPreset.allCases.first {
            $0.focusMinutes == focusMinutes &&
            $0.shortBreakMinutes == shortBreakMinutes &&
            $0.longBreakMinutes == longBreakMinutes
        }
    }

    mutating func apply(_ preset: TimerPreset) {
        focusMinutes = preset.focusMinutes
        shortBreakMinutes = preset.shortBreakMinutes
        longBreakMinutes = preset.longBreakMinutes
    }
}

// MARK: - Persistence container

struct StoreData: Codable {
    var tasks: [PomoTask] = []
    var sessions: [PomoSession] = []
    var settings: AppSettings = AppSettings()
}
