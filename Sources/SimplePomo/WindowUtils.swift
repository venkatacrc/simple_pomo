import SwiftUI
import AppKit

// MARK: - Window IDs

enum WindowID {
    static let main = "main"
    static let mini = "mini"
}

// MARK: - Shared window state

/// Tracks whether the app is currently in "mini" (floating pill) mode so
/// buttons and menu items in either window can drive a symmetric toggle.
@MainActor
final class WindowController: ObservableObject {
    @Published private(set) var isMini: Bool = false

    func enterMini(open: OpenWindowAction, dismiss: DismissWindowAction) {
        open(id: WindowID.mini)
        dismiss(id: WindowID.main)
        isMini = true
    }

    func exitMini(open: OpenWindowAction, dismiss: DismissWindowAction) {
        open(id: WindowID.main)
        dismiss(id: WindowID.mini)
        isMini = false
    }

    func toggle(open: OpenWindowAction, dismiss: DismissWindowAction) {
        isMini ? exitMini(open: open, dismiss: dismiss)
               : enterMini(open: open, dismiss: dismiss)
    }
}

// MARK: - Access the underlying NSWindow

/// Lets a SwiftUI view reach into its hosting `NSWindow` to configure things
/// that aren't (yet) exposed in the pure SwiftUI scene API, e.g.
/// `.level = .floating`, `isMovableByWindowBackground = true`.
///
/// Usage:
///     .background(WindowAccessor { window in
///         window.level = .floating
///     })
struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Reapply on any update in case macOS reset the window state.
        DispatchQueue.main.async {
            if let window = nsView.window {
                configure(window)
            }
        }
    }
}
