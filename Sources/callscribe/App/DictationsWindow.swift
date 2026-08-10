import AppKit
import SwiftUI

/// Hosts `DictationsView` in a plain AppKit window, created on first use and
/// reused thereafter.
///
/// Deliberately **not** a second SwiftUI `Window` scene. The first attempt at
/// this feature added one, and while that turned out not to be the cause of the
/// input bug that followed, an `NSWindow` is the pattern already proven to work
/// in this app (`DictationHUD` does the same for the overlay) and it keeps the
/// scene graph as it was — one `Window` plus the `MenuBarExtra`.
///
/// Unlike the HUD's panel this window *should* take focus: you come here to read,
/// search and copy.
@MainActor
final class DictationsWindow {
    private let history: DictationHistory
    private var window: NSWindow?

    init(history: DictationHistory) {
        self.history = history
    }

    func show() {
        // Re-read on every open: an external write (the `dictate` CLI, or the file
        // edited by hand) is invisible otherwise — this app has no file watching.
        history.reload()

        let window = window ?? make()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func make() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dictations"
        window.contentView = NSHostingView(
            rootView: DictationsView(history: history).tint(.brand))
        window.setContentSize(NSSize(width: 560, height: 620))
        window.contentMinSize = NSSize(width: 460, height: 400)
        // Closing must not deallocate it — we hold the reference and reopen it.
        window.isReleasedWhenClosed = false
        // Centre first, then let a remembered frame override it. The reverse order
        // would restore the saved position and immediately re-centre over it.
        window.center()
        window.setFrameAutosaveName("dictations")
        window.setFrameUsingName("dictations")
        return window
    }
}
