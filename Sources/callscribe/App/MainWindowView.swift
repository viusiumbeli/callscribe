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
                Text(RecordStatus.text(state.phase))
                    .foregroundStyle(state.isRecording ? Color.red : Color.secondary)
                if case .done(let folder) = state.phase {
                    Button { NSWorkspace.shared.open(folder) } label: {
                        Label("Open Last Call", systemImage: "folder")
                    }
                }
                RecordButton(state: state)
                    .keyboardShortcut("r")
            }
        }
    }
}
