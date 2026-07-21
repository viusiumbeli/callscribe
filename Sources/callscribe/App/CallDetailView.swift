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
    @State private var enrolledNames: Set<String> = []
    @State private var expectedCount = 0   // 0 = Auto, else number of remote speakers
    @State private var selectedLabel = ""
    @State private var renameTo = ""
    @State private var player = CallAudioPlayer()
    @State private var showTranscript = true
    @State private var showSpeakers = true
    @State private var confirmingDelete = false
    @State private var actionError: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            // Processing status pinned at the very top, above the player.
            if let stage = state.processingStage(for: call.folder) {
                processingHeader(stage)
            }

            // The player stays pinned at the top so play/pause + scrubbing are
            // reachable while a long transcript scrolls underneath.
            if player.isReady {
                pinnedAudioBar
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
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
                .padding(Spacing.xl)
            }
        }
        .onChange(of: call.id, initial: true) { _, _ in load() }
        // Reload when this call finishes background processing so its transcript
        // and summary appear without reopening.
        .onChange(of: state.isProcessing(call.folder)) { _, _ in load() }
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

    /// Background-processing status as a fixed header pinned above the player,
    /// styled to match `pinnedAudioBar` so the two bars stack cleanly.
    private func processingHeader(_ stage: String) -> some View {
        HStack(spacing: Spacing.sm) {
            ProgressView().controlSize(.small)
            Text("Processing — \(CallFormatting.stageLabel(stage))")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
        }
    }

    /// The player as a compact fixed header (material + hairline bottom border)
    /// so the transcript scrolls under it.
    private var pinnedAudioBar: some View {
        playbackBar
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.md)
            .background(.regularMaterial)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            }
    }

    private var playbackBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(LinearGradient.brand, in: Circle())
                }
                .buttonStyle(.plain)
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
        HStack(spacing: Spacing.sm) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transcript, forType: .string)
            } label: {
                Label("Copy Transcript", systemImage: "doc.on.doc")
            }
            .buttonStyle(SoftButtonStyle())
            .disabled(transcript.isEmpty)
            .pointerCursor()

            // Always available: create the summary if missing, or regenerate
            // it (e.g. to get a title / speaker names) when it already exists.
            Button {
                run { try await state.retrySummary(for: call.folder) }
            } label: {
                Label(summary.isEmpty ? "Retry Summary" : "Regenerate Summary", systemImage: "sparkles")
            }
            .buttonStyle(SoftButtonStyle(tint: .brand))
            .disabled(busy || transcript.isEmpty)
            .pointerCursor()

            Spacer()

            // Pick up an interactive Claude Code session in the project folder.
            Button {
                TerminalLauncher.openClaude(in: state.selectedProject.rootURL)
            } label: {
                Label("Claude Code", systemImage: "terminal")
            }
            .buttonStyle(SoftButtonStyle())
            .help("Open Terminal with Claude Code in the project folder")

            // Only needed to grab the raw files (audio, markdown) out of the folder.
            Button {
                NSWorkspace.shared.open(call.folder.url)
            } label: {
                Label("Open Folder", systemImage: "folder")
            }
            .buttonStyle(SoftButtonStyle())
            .help("Open this call's folder in Finder")
            .pointerCursor()

            Button {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(SoftButtonStyle(tint: .red))
            .help("Delete this recording and all of its files")
            .pointerCursor()
        }
    }

    private var renameControls: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Rename the selected speaker.
            VStack(alignment: .leading, spacing: Spacing.sm) {
                groupLabel("Rename")
                HStack(spacing: Spacing.sm) {
                    Menu {
                        ForEach(speakerLabels, id: \.self) { label in
                            Button(names[label].map { "\(label) → \($0)" } ?? label) {
                                selectedLabel = label
                                renameTo = names[label] ?? ""
                            }
                        }
                    } label: {
                        menuField(names[selectedLabel].map { "\(selectedLabel) → \($0)" } ?? selectedLabel, width: 200)
                    }
                    .menuStyle(.borderlessButton)
                    .pointerCursor()

                    TextField("Name", text: $renameTo)
                        .textFieldStyle(.plain)
                        .frame(width: 170)
                        .softField()

                    Button("Rename") {
                        guard !selectedLabel.isEmpty else { return }
                        run { try await state.rename(selectedLabel, to: renameTo, in: call.folder) }
                    }
                    .buttonStyle(SoftButtonStyle(tint: .brand))
                    .disabled(busy)
                }
            }

            // Voice enrollment: learn this speaker's voice so future calls label
            // them by name automatically. Not for "Me" (that's always the mic).
            if selectedLabel != "Me" && selectedLabel != "Participant" && !selectedLabel.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    groupLabel("Voice")
                    HStack(spacing: Spacing.sm) {
                        Button {
                            run { try await state.enrollVoice(label: selectedLabel, name: enrollName, in: call.folder) }
                        } label: {
                            Label("Remember voice", systemImage: "waveform.badge.plus")
                        }
                        .buttonStyle(SoftButtonStyle(tint: .brand))
                        .disabled(busy || enrollName.isEmpty)
                        .help("Learn this speaker's voice to recognise them on future calls")

                        if let enrolled = enrolledNameForSelection {
                            Button {
                                run { try await state.forgetVoice(name: enrolled, in: call.folder) }
                            } label: {
                                Label("Forget", systemImage: "waveform.slash")
                            }
                            .buttonStyle(SoftButtonStyle(tint: .red))
                            .disabled(busy)
                            .help("Forget this learned voice")

                            Label("voice saved", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(.green)
                        }
                    }
                }
            }

            // Force how many remote people to split into when auto-detection
            // merges or over-splits them.
            VStack(alignment: .leading, spacing: Spacing.sm) {
                groupLabel("Other speakers")
                HStack(spacing: Spacing.sm) {
                    Menu {
                        Button("Auto") { expectedCount = 0 }
                        ForEach(1...8, id: \.self) { n in Button("\(n)") { expectedCount = n } }
                    } label: {
                        menuField(expectedCount == 0 ? "Auto" : "\(expectedCount)", width: 90)
                    }
                    .menuStyle(.borderlessButton)
                    .pointerCursor()

                    Button("Re-detect") {
                        run { try await state.setExpectedSpeakers(expectedCount == 0 ? nil : expectedCount,
                                                                  for: call.folder) }
                    }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(busy)
                    .help("Re-run speaker detection with this number of participants")
                }
            }
        }
    }

    /// Small uppercase caption heading for a sub-group of controls.
    private func groupLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    /// A soft, borderless dropdown trigger (value + chevron) matching the inputs.
    private func menuField(_ text: String, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(text).lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: width, alignment: .leading)
        .softField()
        .contentShape(Rectangle())
    }

    /// The name to enroll under — what's in the field, else the selected label
    /// itself when it's already a real name (an enrolled `.named` speaker).
    private var enrollName: String {
        let typed = renameTo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return selectedLabel.hasPrefix("Speaker ") ? "" : selectedLabel
    }

    /// The enrolled voice matching the selected speaker (by its name or label),
    /// if any — drives the "forget" button.
    private var enrolledNameForSelection: String? {
        [names[selectedLabel], selectedLabel]
            .compactMap { $0 }
            .first { enrolledNames.contains($0) }
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
        enrolledNames = state.enrolledVoiceNames()
        expectedCount = state.expectedSpeakers(for: call.folder) ?? 0
        turns = Self.loadTurns(folder: call.folder, transcript: transcript, names: names)
        speakerLabels = Self.orderedLabels(turns)
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

    /// The distinct canonical speaker labels ("Me", "Speaker 1", or a
    /// voice-matched name), in first-appearance order. Taken straight from the
    /// canonical turns so each speaker is a stable, separate entry — renaming one
    /// (a display-name override) can never merge it with another.
    static func orderedLabels(_ turns: [Turn]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for turn in turns where seen.insert(turn.label).inserted {
            result.append(turn.label)
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
