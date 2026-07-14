import AppKit
import CallScribeEngine
import SwiftUI

struct MenuBarView: View {
    var body: some View {
        Text("CallScribe \(AppInfo.version)")
        Divider()
        // Temporary M1 verification item: exercises capture + TCC prompts
        // under the app's own identity. Removed in M6.
        Button("Run 10s Audio Probe") { runProbe() }
        Divider()
        Button("Quit CallScribe") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func runProbe() {
        Task {
            do {
                let result = try await ProbeRunner.run(seconds: 10)
                NSWorkspace.shared.activateFileViewerSelecting([result.micURL, result.systemURL])
            } catch {
                NSLog("Probe failed: \(error.localizedDescription)")
            }
        }
    }
}
