import SwiftUI

struct HistoryView: View {
    @Bindable var state: AppState
    @State private var selection: AppState.CallSummary.ID?

    var body: some View {
        NavigationSplitView {
            List(state.calls, selection: $selection) { call in
                VStack(alignment: .leading, spacing: 2) {
                    Text(call.name).font(.body)
                    if let dur = call.durationSec {
                        Text("\(Int(dur)) s").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tag(call.id)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .toolbar {
                Button { state.refreshHistory() } label: { Image(systemName: "arrow.clockwise") }
            }
        } detail: {
            if let selected = state.calls.first(where: { $0.id == selection }) {
                CallDetailView(state: state, call: selected)
            } else {
                ContentUnavailableView("No call selected", systemImage: "waveform")
            }
        }
        .onAppear { state.refreshHistory() }
    }
}
