import AppKit
import CallScribeCore
import SwiftUI

struct CallDetailView: View {
    @Bindable var state: AppState
    let call: AppState.CallSummary

    @State private var transcript = ""
    @State private var summary = ""
    @State private var names: [String: String] = [:]
    @State private var speakerLabels: [String] = []
    @State private var selectedLabel = ""
    @State private var renameTo = ""
    @State private var player = CallAudioPlayer()
    @State private var showAudio = true
    @State private var showTranscript = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                actions

                if player.isReady {
                    collapsibleSection("Audio", isExpanded: $showAudio) { playbackBar }
                }

                if !summary.isEmpty {
                    SummaryView(markdown: summary) { index in toggleTask(index) }
                }

                if !speakerLabels.isEmpty { renameControls }

                collapsibleSection("Transcript", isExpanded: $showTranscript) {
                    Text(transcript.isEmpty ? "No transcript." : transcript)
                        .textSelection(.enabled)
                        .font(.system(.body, design: .default))
                }
            }
            .padding()
        }
        .onChange(of: call.id, initial: true) { _, _ in load() }
        .onDisappear { player.teardown() }
        .navigationTitle(HistoryView.title(for: call))
    }

    // MARK: - Playback

    private var playbackBar: some View {
        HStack(spacing: 12) {
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 20)
            }
            .buttonStyle(.borderedProminent)

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
    }

    // MARK: - Actions

    private var actions: some View {
        HStack {
            Button("Copy Transcript") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transcript, forType: .string)
            }
            .disabled(transcript.isEmpty)

            if summary.isEmpty {
                Button("Retry Summary") { state.retrySummary(for: call.folder) }
            }

            Spacer()

            // Only needed to grab the raw files (audio, markdown) out of the folder.
            Button {
                NSWorkspace.shared.open(call.folder.url)
            } label: {
                Label("Open Folder", systemImage: "folder")
            }
            .help("Open this call's folder in Finder")
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
                state.rename(selectedLabel, to: renameTo, in: call.folder)
                Task { try? await Task.sleep(for: .milliseconds(400)); load() }
            }
        }
        .font(.callout)
    }

    private func collapsibleSection<Content: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let inner = content()
        return DisclosureGroup(isExpanded: isExpanded) {
            inner
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Text(title).font(.headline)
        }
    }

    private func load() {
        transcript = (try? String(contentsOf: call.folder.transcriptMD, encoding: .utf8)) ?? ""
        summary = (try? String(contentsOf: call.folder.summaryMD, encoding: .utf8)) ?? ""
        names = (try? call.folder.loadMeta().speakerNames) ?? [:]
        speakerLabels = Self.labels(in: transcript, names: names)
        if !speakerLabels.contains(selectedLabel) { selectedLabel = speakerLabels.first ?? "" }
        renameTo = names[selectedLabel] ?? ""
        player.load(call.folder)
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
}
