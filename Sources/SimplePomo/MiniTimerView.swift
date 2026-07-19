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
        HStack(spacing: 0) {
            phaseBar
            HStack(spacing: 5) {
                Text(timer.displayTime)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))

                Spacer(minLength: 2)

                iconButton(
                    systemName: timer.isRunning ? "pause.fill" : "play.fill",
                    size: 18,
                    iconSize: 9,
                    tint: 0.24,
                    help: timer.isRunning ? "Pause" : "Start"
                ) {
                    timer.toggle()
                }
                .keyboardShortcut(.space, modifiers: [])

                iconButton(
                    systemName: "minus",
                    size: 16,
                    iconSize: 10,
                    tint: 0.16,
                    help: "Minimize to Dock (⌘M)"
                ) {
                    NSApp.keyWindow?.miniaturize(nil)
                }

                iconButton(
                    systemName: "arrow.up.left.and.arrow.down.right",
                    size: 16,
                    iconSize: 8,
                    tint: 0.16,
                    help: "Expand to full window (⌘⇧M)"
                ) {
                    windows.exitMini(open: openWindow, dismiss: dismissWindow)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(width: 140, height: 40)
        .background(background)
        .background(WindowAccessor(configure: configureWindow))
    }

    // MARK: - Pieces

    private var background: some View {
        LinearGradient(
            colors: [
                timer.phase.accentBackground.opacity(0.96),
                Color.black.opacity(0.88)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .overlay(Rectangle().fill(Color.black.opacity(timer.isRunning ? 0.05 : 0.30)))
    }

    /// A slim vertical strip of the current phase's tint along the leading edge.
    private var phaseBar: some View {
        Rectangle()
            .fill(timer.phase.tint)
            .frame(width: 4)
            .opacity(timer.isRunning ? 1.0 : 0.6)
    }

    /// Small circular icon button used for play/pause, minimize, expand.
    private func iconButton(
        systemName: String,
        size: CGFloat,
        iconSize: CGFloat,
        tint: Double,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .bold))
                .frame(width: size, height: size)
                .foregroundStyle(.white)
                .background(Circle().fill(Color.white.opacity(tint)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
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
        window.styleMask.insert(.miniaturizable)   // enables ⌘M and Dock miniaturize
        window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
        // We provide our own play/minimize/expand buttons in the pill, so hide
        // the standard traffic lights entirely.
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        // Round the whole window to match the SwiftUI content.
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 10
            contentView.layer?.masksToBounds = true
        }
    }
}
