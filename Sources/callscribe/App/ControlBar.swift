import AppKit
import SwiftUI

/// Human-readable status string for a recording phase.
enum RecordStatus {
    static func text(_ phase: AppState.Phase) -> String {
        switch phase {
        case .idle: "Ready"
        case .recording(let elapsed): "Recording  \(clock(elapsed))"
        case .processing(let stage): "Processing: \(stage)…"
        case .done: "Done"
        case .failed: "Error"
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let t = Int(seconds)
        return String(format: "%02d:%02d", t / 60, t % 60)
    }
}

/// The Start / Stop / Processing button, shared by the window toolbar and the
/// tray menu.
struct RecordButton: View {
    @Bindable var state: AppState

    var body: some View {
        switch state.phase {
        case .recording:
            Button { state.stopRecording() } label: {
                Label("Stop & Transcribe", systemImage: "stop.circle.fill")
            }
        case .processing:
            Button {} label: { Label("Processing…", systemImage: "hourglass") }
                .disabled(true)
        default:
            Button { state.startRecording() } label: {
                Label("Start Recording", systemImage: "record.circle")
            }
        }
    }
}

/// Recording controls rendered as menu items for the MenuBarExtra tray.
struct ControlBar: View {
    @Bindable var state: AppState

    var body: some View {
        Text(RecordStatus.text(state.phase))
        Divider()
        RecordButton(state: state)
        if case .done(let folder) = state.phase {
            Button("Open Last Call") { NSWorkspace.shared.open(folder) }
        }
    }
}
