import AppKit
import SwiftUI

struct CallScribeApp: App {
    @State private var state = AppState()

    init() {
        // LSUIElement covers the bundled case; this covers bare-binary runs.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            Image(systemName: state.isRecording ? "waveform.circle.fill" : "waveform.circle")
        }

        Window("CallScribe History", id: "history") {
            HistoryView(state: state)
        }
        .defaultSize(width: 720, height: 480)
    }
}
