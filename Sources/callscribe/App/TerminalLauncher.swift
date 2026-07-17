import AppKit
import CallScribeEngine
import Foundation

/// Opens Terminal running the `claude` (Claude Code) CLI in a directory. Uses a
/// temp `.command` file opened via NSWorkspace (Terminal is the default handler)
/// rather than scripting Terminal — so it needs no Automation permission.
enum TerminalLauncher {
    static func openClaude(in directory: URL) {
        // GUI apps don't inherit the shell PATH; use the resolved binary when we
        // can find it, else fall back to bare `claude` (Terminal's login shell
        // has PATH).
        let command = ClaudeCLISummarizer.resolveBinary().map { shellQuote($0.path) } ?? "claude"
        let script = """
        #!/bin/bash
        cd \(shellQuote(directory.path)) || exit 1
        clear
        exec \(command)
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("callscribe-claude.command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            // Best-effort; nothing to surface if the temp write fails.
        }
    }

    /// Wrap a string in single quotes for safe use in the shell script.
    private static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
