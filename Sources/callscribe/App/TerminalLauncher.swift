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
        } catch {
            return   // best-effort; nothing to surface if the temp write fails
        }

        // macOS has no "default terminal" setting — `.command` opens in Terminal
        // by default. Prefer iTerm2 when it's installed (it runs .command too);
        // otherwise use the default handler.
        let workspace = NSWorkspace.shared
        if let iterm = workspace.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") {
            workspace.open([url], withApplicationAt: iterm, configuration: NSWorkspace.OpenConfiguration())
        } else {
            workspace.open(url)
        }
    }

    /// Wrap a string in single quotes for safe use in the shell script.
    private static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
