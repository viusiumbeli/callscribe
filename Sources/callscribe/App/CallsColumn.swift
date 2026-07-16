import SwiftUI

/// Middle column: the selected project's calls, with the record button pinned
/// on top and calls grouped into day sections.
struct CallsColumn: View {
    @Bindable var state: AppState
    @Binding var selection: String?

    @State private var pendingDelete: AppState.CallSummary?

    var body: some View {
        VStack(spacing: 0) {
            recordHeader
            List(selection: $selection) {
                ForEach(daySections) { section in
                    Section(section.title) {
                        ForEach(section.calls) { call in
                            callRow(call)
                                .tag(call.id)
                                .contextMenu {
                                    Button("Delete", role: .destructive) { pendingDelete = call }
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .confirmationDialog(
            "Delete this recording?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { call in
            Button("Delete recording and all its files", role: .destructive) {
                if selection == call.id { selection = nil }
                state.delete(call.folder)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("This permanently removes the whole folder — audio, transcript, summary and everything else for this call.")
        }
    }

    /// Prominent recording control pinned above the call list.
    private var recordHeader: some View {
        VStack(spacing: Spacing.sm) {
            RecordButton(state: state)
                .buttonStyle(BrandButtonStyle(
                    fill: state.isRecording ? AnyShapeStyle(Color.red) : AnyShapeStyle(LinearGradient.brand),
                    glow: state.isRecording ? .red : .brand))
                .frame(maxWidth: .infinity)
                .keyboardShortcut("r")

            if case .idle = state.phase {} else {
                RecordStatusChip(phase: state.phase)
            }
        }
        .padding(Spacing.lg)
    }

    private func callRow(_ call: AppState.CallSummary) -> some View {
        let sub = CallFormatting.subtitle(call)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(call.title ?? CallFormatting.time(call))
                .font(.body.weight(.medium)).lineLimit(2)
            if !sub.isEmpty {
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    /// Calls grouped into day sections (newest first), preserving order.
    private var daySections: [DaySection] {
        let calendar = Calendar.current
        var order: [Date] = []
        var byDay: [Date: [AppState.CallSummary]] = [:]
        for call in state.calls {
            let day = call.startedAt.map { calendar.startOfDay(for: $0) } ?? .distantPast
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(call)
        }
        return order.map { day in
            DaySection(id: "\(day.timeIntervalSince1970)", title: CallFormatting.dayTitle(day), calls: byDay[day] ?? [])
        }
    }

    struct DaySection: Identifiable {
        let id: String
        let title: String
        let calls: [AppState.CallSummary]
    }
}
