import AppKit
import SwiftUI

/// The recording controls + status, shared by the main window and the tray menu.
/// `compact` renders as menu items (for MenuBarExtra); otherwise a horizontal bar.
struct ControlBar: View {
    @Bindable var state: AppState
    var compact = false

    var body: some View {
        if compact {
            Text(statusText)
            Divider()
            recordButton
            if case .done(let folder) = state.phase {
                Button("Open Last Call") { NSWorkspace.shared.open(folder) }
            }
        } else {
            HStack(spacing: 12) {
                statusView
                Spacer()
                if case .done(let folder) = state.phase {
                    Button("Open Last Call") { NSWorkspace.shared.open(folder) }
                }
                recordButton
                    .keyboardShortcut("r")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder private var recordButton: some View {
        switch state.phase {
        case .recording:
            Button("■ Stop & Transcribe") { state.stopRecording() }
        case .processing:
            Button("Processing…") {}.disabled(true)
        default:
            Button("● Start Recording") { state.startRecording() }
        }
    }

    @ViewBuilder private var statusView: some View {
        switch state.phase {
        case .recording:
            Label(statusText, systemImage: "record.circle").foregroundStyle(.red)
        case .processing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(statusText) }
        case .failed:
            Label(statusText, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        default:
            Text(statusText).foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch state.phase {
        case .idle: "Ready"
        case .recording(let elapsed): "Recording  \(Self.clock(elapsed))"
        case .processing(let stage): "Processing: \(stage)…"
        case .done: "✓ Done"
        case .failed(let message): "⚠️ \(message)"
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let t = Int(seconds)
        return String(format: "%02d:%02d", t / 60, t % 60)
    }
}
