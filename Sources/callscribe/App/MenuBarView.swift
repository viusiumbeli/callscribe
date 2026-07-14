import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        statusLine
        Divider()

        switch state.phase {
        case .recording:
            Button("■ Stop & Transcribe") { state.stopRecording() }
        case .processing:
            Text("Processing…").disabled(true)
        default:
            Button("● Start Recording") { state.startRecording() }
        }

        if case .done(let folder) = state.phase {
            Button("Open Last Call") { NSWorkspace.shared.open(folder) }
        }

        Divider()
        Button("History…") { openWindow(id: "history") }
        Button("Quit CallScribe") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder private var statusLine: some View {
        switch state.phase {
        case .idle:
            Text("CallScribe — ready")
        case .recording(let elapsed):
            Text("● Recording  \(Self.clock(elapsed))")
        case .processing(let stage):
            Text("Processing: \(stage)…")
        case .done:
            Text("✓ Done")
        case .failed(let message):
            Text("⚠️ \(message)")
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let t = Int(seconds)
        return String(format: "%02d:%02d", t / 60, t % 60)
    }
}
