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

    var durationSeconds: Int {
        max(0, Int(endedAt.timeIntervalSince(startedAt)))
    }

    var durationMinutes: Double {
        Double(durationSeconds) / 60.0
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
}

// MARK: - Persistence container

struct StoreData: Codable {
    var tasks: [PomoTask] = []
    var sessions: [PomoSession] = []
    var settings: AppSettings = AppSettings()
}
