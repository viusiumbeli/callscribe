import CallScribeCore
import Foundation

/// Summarizer #1: shells out to the locally installed `claude -p` CLI. Sends
/// the transcript on stdin, reads Markdown on stdout. A missing binary, a
/// non-zero exit, or a timeout raises a typed error — the caller keeps the
/// transcript and offers a retry; summarization never blocks the pipeline.
public struct ClaudeCLISummarizer: Summarizer {
    public enum Failure: LocalizedError {
        case binaryNotFound
        case timedOut
        case nonZeroExit(Int32, String)

        public var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                "The `claude` CLI was not found. Install it or set CALLSCRIBE_CLAUDE_PATH."
            case .timedOut:
                "The summarizer timed out."
            case .nonZeroExit(let code, let stderr):
                "claude exited with code \(code): \(stderr)"
            }
        }
    }

    private let binaryURL: URL
    private let timeout: TimeInterval

    public init?(timeout: TimeInterval = 180) {
        guard let binary = Self.resolveBinary() else { return nil }
        self.binaryURL = binary
        self.timeout = timeout
    }

    /// CALLSCRIBE_CLAUDE_PATH → common install locations. GUI apps don't inherit
    /// the shell PATH, so probe explicit paths rather than relying on `which`.
    static func resolveBinary() -> URL? {
        if let override = ProcessInfo.processInfo.environment["CALLSCRIBE_CLAUDE_PATH"] {
            let url = URL(fileURLWithPath: override)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        return candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    public func summarize(transcript: String) async throws -> SummaryResult {
        let prompt = SummaryPrompt.build(transcript: transcript)
        let output = try runClaude(prompt: prompt)
        return SummaryPrompt.parse(output)
    }

    private func runClaude(prompt: String) throws -> String {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["-p"]

        // Run in a throwaway empty directory so the `claude` agent doesn't scan
        // the user's real folders (Desktop/Documents/…) as a "project" — those
        // accesses would otherwise surface as TCC prompts attributed to this app.
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("callscribe-claude", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        process.currentDirectoryURL = scratch

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        stdin.fileHandleForWriting.write(Data(prompt.utf8))
        try? stdin.fileHandleForWriting.close()

        // Read concurrently so a large response can't deadlock on a full pipe.
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            throw Failure.timedOut
        }

        guard process.terminationStatus == 0 else {
            throw Failure.nonZeroExit(
                process.terminationStatus,
                String(decoding: errData, as: UTF8.self)
            )
        }
        return String(decoding: outData, as: UTF8.self)
    }
}
