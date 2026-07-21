import AppKit
import SwiftUI

/// Human-readable status string for a recording phase.
enum RecordStatus {
    static func text(_ phase: AppState.Phase) -> String {
        switch phase {
        case .idle: "Ready"
        case .recording(let elapsed): "Recording  \(clock(elapsed))"
        case .failed: "Error"
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let t = Int(seconds)
        return String(format: "%02d:%02d", t / 60, t % 60)
    }
}

/// A small status pill for the toolbar: icon + recording status.
struct RecordStatusChip: View {
    let phase: AppState.Phase

    var body: some View {
        HStack(spacing: 5) {
            icon
            Text(RecordStatus.text(phase)).font(.callout)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }

    @ViewBuilder private var icon: some View {
        switch phase {
        case .recording:
            Image(systemName: "record.circle").foregroundStyle(.red)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .idle:
            Image(systemName: "circle")
        }
    }
}

/// The Start / Stop button, shared by the window toolbar and the tray menu.
/// Recording and background processing are independent, so this is never
/// blocked by processing.
struct RecordButton: View {
    @Bindable var state: AppState

    var body: some View {
        if state.isRecording {
            Button { state.stopRecording() } label: {
                Label("Stop & Transcribe", systemImage: "stop.circle.fill")
            }
        } else {
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
        if state.isRecording {
            Button("Cancel Recording") { state.cancelRecording() }
        }
        if state.processingCount > 0 {
            Text("Processing \(state.processingCount) call\(state.processingCount > 1 ? "s" : "")…")
        }
    }
}
