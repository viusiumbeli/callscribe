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
            HStack(spacing: 14) {
                Image(systemName: state.isRecording ? "waveform.circle.fill" : "waveform.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(state.isRecording ? Color.red : Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CallScribe").font(.headline)
                    statusView.font(.callout)
                }

                Spacer()

                if case .done(let folder) = state.phase {
                    Button("Open Last Call") { NSWorkspace.shared.open(folder) }
                        .controlSize(.large)
                }
                recordButton
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut("r")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    @ViewBuilder private var recordButton: some View {
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

    @ViewBuilder private var statusView: some View {
        switch state.phase {
        case .recording:
            Label(statusText, systemImage: "record.circle").foregroundStyle(.red)
        case .processing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(statusText) }
        case .failed(let message):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(message)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .help(message)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy the full error text")
            }
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
