import SwiftUI

/// The app's primary window: the call history, with the recording button
/// pinned above the list (see HistoryView). Recording-flow errors (global)
/// show as a copyable banner across the top.
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
    }
}
