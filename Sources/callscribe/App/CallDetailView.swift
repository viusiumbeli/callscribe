import AppKit
import CallScribeCore
import SwiftUI

struct CallDetailView: View {
    @Bindable var state: AppState
    let call: AppState.CallSummary
    /// Called after the call is deleted, so the list can clear its selection.
    var onDeleted: () -> Void = {}

    @State private var transcript = ""
    @State private var turns: [Turn] = []
    @State private var summary = ""
    @State private var names: [String: String] = [:]
    @State private var speakerLabels: [String] = []
    @State private var selectedLabel = ""
    @State private var renameTo = ""
    @State private var player = CallAudioPlayer()
    @State private var showAudio = true
    @State private var showTranscript = true
    @State private var showSpeakers = true
    @State private var confirmingDelete = false
    @State private var actionError: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                actions

                if busy {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Working…").foregroundStyle(.secondary)
                    }
                }

                if let actionError {
                    ErrorBanner(message: actionError) { self.actionError = nil }
                }

                if player.isReady {
                    SectionCard(title: "Audio", systemImage: "waveform", isExpanded: $showAudio) {
                        playbackBar
                    }
                }

                if !summary.isEmpty {
                    SummaryView(
                        markdown: summary,
                        onToggle: { index in toggleTask(index) },
                        onDeleteTask: { index in deleteTask(index) }
                    )
                }

                if !speakerLabels.isEmpty {
                    SectionCard(title: "Speakers", systemImage: "person.2", isExpanded: $showSpeakers) {
                        renameControls
                    }
                }

                SectionCard(title: "Transcript", systemImage: "text.quote", isExpanded: $showTranscript) {
                    TranscriptView(turns: turns, names: names, player: player)
                }
            }
            .padding()
        }
        .onChange(of: call.id, initial: true) { _, _ in load() }
        .onDisappear { player.teardown() }
        .confirmationDialog(
            "Delete this recording?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete recording and all its files", role: .destructive) {
                player.teardown()
                state.delete(call.folder)
                onDeleted()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the whole folder — audio, transcript, summary and everything else for this call.")
        }
    }

    // MARK: - Playback

    private var playbackBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 20)
                }
                .buttonStyle(.borderedProminent)
                .pointerCursor()

                Text(CallAudioPlayer.clock(player.currentTime))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 0.1)
                )

                Text(CallAudioPlayer.clock(player.duration))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }

            if player.hasBothTracks {
                HStack(spacing: 8) {
                    Picker("", selection: $player.mode) {
                        Text("Both").tag(CallAudioPlayer.TrackMode.both)
                        Text("Me").tag(CallAudioPlayer.TrackMode.me)
                        Text("Them").tag(CallAudioPlayer.TrackMode.them)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .labelsHidden()
                    if player.mode == .both {
                        Text("recorded on speakers? “Them” avoids the echo")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack {
            Button("Copy Transcript") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transcript, forType: .string)
            }
            .disabled(transcript.isEmpty)
            .pointerCursor()

            // Always available: create the summary if missing, or regenerate
            // it (e.g. to get a title / speaker names) when it already exists.
            Button(summary.isEmpty ? "Retry Summary" : "Regenerate Summary") {
                run { try await state.retrySummary(for: call.folder) }
            }
            .disabled(busy || transcript.isEmpty)
            .pointerCursor()

            Spacer()

            // Only needed to grab the raw files (audio, markdown) out of the folder.
            Button {
                NSWorkspace.shared.open(call.folder.url)
            } label: {
                Label("Open Folder", systemImage: "folder")
            }
            .help("Open this call's folder in Finder")
            .pointerCursor()

            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
            .help("Delete this recording and all of its files")
            .pointerCursor()
        }
    }

    private var renameControls: some View {
        HStack {
            Picker("Speaker", selection: $selectedLabel) {
                ForEach(speakerLabels, id: \.self) { label in
                    Text(names[label].map { "\(label) → \($0)" } ?? label).tag(label)
                }
            }
            .frame(width: 220)
            .onChange(of: selectedLabel) { _, new in renameTo = names[new] ?? "" }

            TextField("Name", text: $renameTo).frame(width: 160)
            Button("Rename") {
                guard !selectedLabel.isEmpty else { return }
                run { try await state.rename(selectedLabel, to: renameTo, in: call.folder) }
            }
            .disabled(busy)
        }
        .font(.callout)
    }

    /// Run a per-call async action, showing a local error on failure.
    private func run(_ operation: @escaping () async throws -> Void) {
        Task {
            busy = true
            actionError = nil
            do {
                try await operation()
                load()
            } catch {
                actionError = error.localizedDescription
            }
            busy = false
        }
    }

    private func load() {
        transcript = (try? String(contentsOf: call.folder.transcriptMD, encoding: .utf8)) ?? ""
        summary = (try? String(contentsOf: call.folder.summaryMD, encoding: .utf8)) ?? ""
        names = (try? call.folder.loadMeta().speakerNames) ?? [:]
        turns = Self.loadTurns(folder: call.folder, transcript: transcript, names: names)
        speakerLabels = Self.labels(in: transcript, names: names)
        if !speakerLabels.contains(selectedLabel) { selectedLabel = speakerLabels.first ?? "" }
        renameTo = names[selectedLabel] ?? ""
        player.load(call.folder)
    }

    /// Build the turns the transcript view renders. Prefer the structured
    /// sidecar (real per-utterance start/end times → precise highlight of
    /// overlapping speech); fall back to parsing `transcript.md` for calls not
    /// re-merged since the sidecar was introduced, estimating each end from a
    /// speaking rate so nested overlaps still highlight sanely.
    static func loadTurns(folder: CallFolder, transcript: String, names: [String: String]) -> [Turn] {
        if let data = try? Data(contentsOf: folder.turnsJSON),
           let t = try? JSONDecoder().decode(Transcript.self, from: data) {
            return t.utterances.enumerated().map { i, u in
                Turn(id: i, start: u.start, end: u.end, label: u.speaker.label, text: u.text)
            }
        }
        let reverse = Dictionary(names.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
        return TranscriptParse.parse(transcript).enumerated().map { i, p in
            let words = p.text.split(separator: " ").count
            return Turn(
                id: i,
                start: p.start,
                end: p.start + max(0.8, Double(words) * 0.4),
                label: reverse[p.label] ?? p.label,
                text: p.text
            )
        }
    }

    /// Canonical speaker labels present in the transcript ("Me", "Speaker 1",
    /// "Participant"), in first-appearance order. A line may already show a
    /// renamed name, so map displayed names back to their canonical label.
    static func labels(in transcript: String, names: [String: String]) -> [String] {
        let reverse = Dictionary(names.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var result: [String] = []
        for line in transcript.split(separator: "\n") {
            guard let match = line.firstMatch(of: /\*\*\[[0-9:]+\]\s+(.+?):\*\*/) else { continue }
            let shown = String(match.1)
            let canonical = reverse[shown] ?? shown
            if seen.insert(canonical).inserted { result.append(canonical) }
        }
        return result
    }

    /// Check/uncheck a "My tasks" item and persist it back to summary.md.
    private func toggleTask(_ index: Int) {
        let updated = SummaryMarkdown.toggleTask(summary, index: index)
        summary = updated
        try? updated.write(to: call.folder.summaryMD, atomically: true, encoding: .utf8)
    }

    /// Delete a "My tasks" item and persist it back to summary.md.
    private func deleteTask(_ index: Int) {
        let updated = SummaryMarkdown.removeTask(summary, index: index)
        summary = updated
        try? updated.write(to: call.folder.summaryMD, atomically: true, encoding: .utf8)
    }
}
