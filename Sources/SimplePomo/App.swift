import SwiftUI
import AppKit

@main
struct SimplePomoApp: App {
    @StateObject private var store: DataStore
    @StateObject private var timer: PomodoroTimer
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        let store = DataStore()
        _store = StateObject(wrappedValue: store)
        _timer = StateObject(wrappedValue: PomodoroTimer(store: store))
    }

    var body: some Scene {
        WindowGroup("Simple Pomo") {
            ContentView()
                .environmentObject(store)
                .environmentObject(timer)
                .frame(minWidth: 960, minHeight: 720)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Timer") {
                Button(timer.isRunning ? "Pause" : "Start") {
                    timer.toggle()
                }
                .keyboardShortcut(.space, modifiers: [])
                Button("Reset") { timer.reset() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Skip") { timer.skip() }
                    .keyboardShortcut("k", modifiers: .command)
                Divider()
                ForEach(Phase.allCases) { phase in
                    Button(phase.title) { timer.switchPhase(phase) }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(timer)
                .frame(width: 480)
                .padding()
        }
    }
}

/// Ensures the app appears in Dock and is brought to the foreground even when
/// launched via `swift run` from a terminal.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
