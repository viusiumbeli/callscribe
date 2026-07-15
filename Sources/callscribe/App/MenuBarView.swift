import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ControlBar(state: state, compact: true)
        Divider()
        Button("Open Window") { openWindow(id: "main") }
        Button("Quit CallScribe") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
