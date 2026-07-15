import SwiftUI

struct HistoryView: View {
    @Bindable var state: AppState
    @State private var selection: AppState.CallSummary.ID?

    var body: some View {
        NavigationSplitView {
            List(state.calls, selection: $selection) { call in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.title(for: call)).font(.body)
                    if let dur = call.durationSec, dur > 0 {
                        Text(Self.duration(dur)).font(.caption).foregroundStyle(.secondary)
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

    /// Friendly call title from its start time, falling back to the folder name.
    static func title(for call: AppState.CallSummary) -> String {
        guard let started = call.startedAt else { return call.name }
        return started.formatted(date: .abbreviated, time: .shortened)
    }

    /// Clean H:MM:SS / M:SS duration (rounded to whole seconds).
    static func duration(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        if t >= 3600 {
            return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
        }
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
