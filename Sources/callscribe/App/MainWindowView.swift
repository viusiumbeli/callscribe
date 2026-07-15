import SwiftUI

/// The app's primary window: recording controls on top, call history below.
struct MainWindowView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            ControlBar(state: state)
            Divider()
            HistoryView(state: state)
        }
        .frame(minWidth: 720, minHeight: 460)
    }
}
