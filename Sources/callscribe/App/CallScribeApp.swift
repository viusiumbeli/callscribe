import AppKit
import SwiftUI

struct CallScribeApp: App {
    @State private var state = AppState()

    var body: some Scene {
        // Primary window — opens automatically at launch (regular app, Dock icon).
        Window("CallScribe", id: "main") {
            MainWindowView(state: state)
        }
        .defaultSize(width: 820, height: 560)

        // Tray icon stays for quick control while the window is closed.
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            Image(systemName: state.isRecording ? "waveform.circle.fill" : "waveform.circle")
        }
    }
}
