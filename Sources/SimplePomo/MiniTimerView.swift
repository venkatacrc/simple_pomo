import SwiftUI
import AppKit

/// A compact, always-on-top pill that shows the current phase color, the
/// remaining time, and controls to play/pause and return to the full window.
struct MiniTimerView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var timer: PomodoroTimer
    @EnvironmentObject var windows: WindowController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ZStack {
            background

            HStack(spacing: 12) {
                phaseDot
                VStack(alignment: .leading, spacing: 1) {
                    Text(timer.displayTime)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: true))
                    Text(subtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 4)
                controls
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 240, height: 72)
        .background(WindowAccessor(configure: configureWindow))
    }

    // MARK: - Pieces

    private var background: some View {
        LinearGradient(
            colors: [
                timer.phase.tint.opacity(0.85),
                timer.phase.accentBackground.opacity(0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Rectangle().fill(Color.black.opacity(timer.isRunning ? 0.15 : 0.35))
        )
    }

    private var phaseDot: some View {
        Circle()
            .fill(.white)
            .frame(width: 10, height: 10)
            .opacity(timer.isRunning ? 1.0 : 0.55)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.4), lineWidth: 4)
                    .scaleEffect(timer.isRunning ? 1.6 : 1.0)
                    .opacity(timer.isRunning ? 0.0 : 0.0)
                    .animation(
                        timer.isRunning
                            ? .easeOut(duration: 1.2).repeatForever(autoreverses: false)
                            : .default,
                        value: timer.isRunning
                    )
            )
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button {
                timer.toggle()
            } label: {
                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(.white)
                    .background(Circle().fill(Color.white.opacity(0.22)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .help(timer.isRunning ? "Pause" : "Start")

            Button {
                windows.exitMini(open: openWindow, dismiss: dismissWindow)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(.white)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .help("Return to full window (⌘⇧M)")
        }
    }

    private var subtitle: String {
        if let task = store.activeTask {
            return task.title
        }
        return timer.phase.title
    }

    // MARK: - NSWindow configuration

    private func configureWindow(_ window: NSWindow) {
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.hasShadow = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.styleMask.remove(.resizable)
        window.styleMask.insert(.fullSizeContentView)
        window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        // Round the whole window
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 14
            contentView.layer?.masksToBounds = true
        }
    }
}
