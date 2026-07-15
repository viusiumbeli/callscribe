import AppKit
import SwiftUI

struct HistoryView: View {
    @Bindable var state: AppState
    @State private var selection: AppState.CallSummary.ID?
    @State private var pendingDelete: AppState.CallSummary?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                recordHeader
                Divider()
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
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .toolbar {
                Button { state.refreshHistory() } label: { Image(systemName: "arrow.clockwise") }
            }
        } detail: {
            if let selected = state.calls.first(where: { $0.id == selection }) {
                CallDetailView(state: state, call: selected) { selection = nil }
                    .id(selected.id)
            } else {
                ContentUnavailableView("No call selected", systemImage: "waveform")
            }
        }
        .onAppear { state.refreshHistory() }
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
        VStack(spacing: 8) {
            projectPicker

            RecordButton(state: state)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(state.isRecording ? Color.red : Color.accentColor)
                .frame(maxWidth: .infinity)
                .keyboardShortcut("r")

            if case .idle = state.phase {} else {
                RecordStatusChip(phase: state.phase)
            }
        }
        .padding(12)
    }

    /// Project selector: pick where recordings are stored / claude runs, or add
    /// a new project pointing at a folder you choose.
    private var projectPicker: some View {
        Menu {
            ForEach(state.projects) { project in
                Button {
                    state.selectedProjectID = project.id
                } label: {
                    if project.id == state.selectedProjectID {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }
            Divider()
            Button("Add Project…") { addProject() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                Text(state.selectedProject.name).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
        }
        .menuStyle(.borderlessButton)
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a folder for this project's recordings"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.addProject(name: url.lastPathComponent, url: url)
    }

    /// One call row: the LLM title (or the time, if untitled) plus time/duration.
    private func callRow(_ call: AppState.CallSummary) -> some View {
        let sub = Self.subtitle(call)
        return VStack(alignment: .leading, spacing: 2) {
            Text(call.title ?? Self.timeText(call)).font(.body).lineLimit(2)
            if !sub.isEmpty {
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Calls grouped into day sections (newest first), preserving call order.
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
            DaySection(
                id: "\(day.timeIntervalSince1970)",
                title: Self.dayTitle(day),
                calls: byDay[day] ?? []
            )
        }
    }

    struct DaySection: Identifiable {
        let id: String
        let title: String
        let calls: [AppState.CallSummary]
    }

    /// Title/detail-window title: prefer the LLM name, else the start date.
    static func title(for call: AppState.CallSummary) -> String {
        if let t = call.title, !t.isEmpty { return t }
        guard let started = call.startedAt else { return call.name }
        return started.formatted(date: .abbreviated, time: .shortened)
    }

    static func timeText(_ call: AppState.CallSummary) -> String {
        call.startedAt?.formatted(date: .omitted, time: .shortened) ?? call.name
    }

    static func subtitle(_ call: AppState.CallSummary) -> String {
        var parts: [String] = []
        if call.title != nil { parts.append(timeText(call)) }   // keep the time visible
        if let dur = call.durationSec, dur > 0 { parts.append(duration(dur)) }
        return parts.joined(separator: " · ")
    }

    static func dayTitle(_ day: Date) -> String {
        if day == .distantPast { return "Earlier" }
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
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
