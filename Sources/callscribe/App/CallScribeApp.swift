import AppKit
import SwiftUI

struct CallScribeApp: App {
    @State private var state = AppState()
    @State private var dictation = DictationController()

    var body: some Scene {
        // Primary window — opens automatically at launch (regular app, Dock icon).
        Window("CallScribe", id: "main") {
            MainWindowView(state: state, dictation: dictation)
                .tint(.brand)
                // Dictation and call recording share one microphone, so dictation
                // stands down while a call is being recorded. Wired here rather
                // than inside either object: it's the one place that owns both.
                .onAppear { dictation.isBlocked = { state.isRecording } }
        }
        .defaultSize(width: 1000, height: 640)

        // Tray icon stays for quick control while the window is closed.
        MenuBarExtra {
            MenuBarView(state: state, dictation: dictation)
                .tint(.brand)
        } label: {
            Image(systemName: state.isRecording ? "waveform.circle.fill" : "waveform.circle")
        }
    }
}
