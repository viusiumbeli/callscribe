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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

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
        .navigationTitle(call.name)
    }

    private var header: some View {
        HStack {
            Button("Open Folder") { NSWorkspace.shared.open(call.folder.url) }
            Button("Copy Transcript") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transcript, forType: .string)
            }
            Button("Export…") { export() }
            if summary.isEmpty {
                Button("Retry Summary") { state.retrySummary(for: call.folder) }
            }
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
                // Reload after the async re-render.
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
