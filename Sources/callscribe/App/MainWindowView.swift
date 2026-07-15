import AppKit
import SwiftUI

/// The app's primary window: recording controls live in the window's title-bar
/// toolbar; the call history fills the body. Recording-flow errors (which are
/// global, not per-call) show as a copyable banner above the history.
struct MainWindowView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            if case .failed(let message) = state.phase {
                ErrorBanner(message: message) { state.clearError() }
                    .padding([.horizontal, .top], 10)
            }
            HistoryView(state: state)
        }
        .frame(minWidth: 720, minHeight: 460)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // "Ready" is just noise in the idle state — only show status
                // once something is happening.
                if case .idle = state.phase {} else {
                    RecordStatusChip(phase: state.phase)
                }
                if case .done(let folder) = state.phase {
                    Button { NSWorkspace.shared.open(folder) } label: {
                        Label("Open Last Call", systemImage: "folder")
                    }
                }
                RecordButton(state: state)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("r")
            }
        }
    }
}
