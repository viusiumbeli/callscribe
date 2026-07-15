import AppKit
import CallScribeCore
import SwiftUI
import UniformTypeIdentifiers

struct CallDetailView: View {
    @Bindable var state: AppState
    let call: AppState.CallSummary

    @State private var transcript = ""
    @State private var summary = ""
    @State private var renameLabel = ""
    @State private var renameTo = ""
    @State private var player = CallAudioPlayer()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                actions

                if player.isReady {
                    section("Audio") { playbackBar }
                }

                if !summary.isEmpty {
                    section("Summary") { Text(.init(summary)).textSelection(.enabled) }
                }

                renameControls

                section("Transcript") {
                    Text(transcript.isEmpty ? "No transcript." : transcript)
                        .textSelection(.enabled)
                        .font(.system(.body, design: .default))
                }
            }
            .padding()
        }
        .onChange(of: call.id, initial: true) { _, _ in load() }
        .onDisappear { player.teardown() }
        .navigationTitle(call.name)
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

            Button("Export…") { export() }
                .disabled(transcript.isEmpty && summary.isEmpty)

            if summary.isEmpty {
                Button("Retry Summary") { state.retrySummary(for: call.folder) }
            }

            Spacer()

            // Secondary: only needed to copy the raw files out of the folder.
            Button {
                NSWorkspace.shared.open(call.folder.url)
            } label: {
                Label("Open Folder", systemImage: "folder")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Open in Finder — only needed to copy the raw audio/files out")
        }
    }

    private var renameControls: some View {
        HStack {
            TextField("Label (e.g. Speaker 1)", text: $renameLabel).frame(width: 160)
            TextField("Name", text: $renameTo).frame(width: 160)
            Button("Rename") {
                guard !renameLabel.isEmpty else { return }
                state.rename(renameLabel, to: renameTo, in: call.folder)
                renameLabel = ""; renameTo = ""
                Task { try? await Task.sleep(for: .milliseconds(400)); load() }
            }
        }
        .font(.callout)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }

    private func load() {
        transcript = (try? String(contentsOf: call.folder.transcriptMD, encoding: .utf8)) ?? ""
        summary = (try? String(contentsOf: call.folder.summaryMD, encoding: .utf8)) ?? ""
        player.load(call.folder)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(call.name).md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let combined = summary.isEmpty ? transcript : "\(summary)\n\n---\n\n\(transcript)"
        try? combined.write(to: url, atomically: true, encoding: .utf8)
    }
}
