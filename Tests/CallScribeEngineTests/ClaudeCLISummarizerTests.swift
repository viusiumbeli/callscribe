import Foundation
import Testing
@testable import CallScribeCore
@testable import CallScribeEngine

// Serialized: these tests mutate the shared CALLSCRIBE_CLAUDE_PATH env var.
@Suite(.serialized) struct ClaudeCLISummarizerTests {
    /// Point the binary override at a tiny stub script and assert we parse its
    /// stdout — no real `claude` needed.
    @Test func stubBinaryProducesSummary() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-stub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let stub = dir.appendingPathComponent("claude")
        try """
        #!/bin/sh
        cat > /dev/null   # consume the prompt on stdin
        printf '## Summary\\nStub summary.\\n\\n```json\\n{"speakers": {"Speaker 1": "Misha"}}\\n```\\n'
        """.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)

        try await withCLaudePath(stub.path) {
            let summarizer = try #require(ClaudeCLISummarizer(log: throwawayLog()))
            let result = try await summarizer.summarize(transcript: "**[00:00:00] Speaker 1:** hi")
            #expect(result.markdown.contains("Stub summary."))
            #expect(result.speakerNames["Speaker 1"] == "Misha")
        }
    }

    @Test func missingBinaryReturnsNilInitializer() async throws {
        try await withCLaudePath("/nonexistent/claude") {
            #expect(ClaudeCLISummarizer() == nil)
        }
    }

    @Test func nonZeroExitThrowsTypedError() async throws {
        try await withCLaudePath("/usr/bin/false") {
            let summarizer = try #require(ClaudeCLISummarizer(log: throwawayLog()))
            await #expect(throws: ClaudeCLISummarizer.Failure.self) {
                _ = try await summarizer.summarize(transcript: "x")
            }
        }
    }

    /// `claude -p` writes its user-facing failures to stdout, not stderr — e.g.
    /// "Not logged in · Please run /login" with an empty stderr. Reporting only
    /// stderr leaves the user with a bare exit code and nothing to act on.
    @Test func nonZeroExitReportsStdoutWhenStderrIsEmpty() async throws {
        let stub = try makeStub(
            """
            #!/bin/sh
            cat > /dev/null
            echo 'Not logged in · Please run /login'
            exit 1
            """)
        defer { try? FileManager.default.removeItem(at: stub.deletingLastPathComponent()) }

        try await withCLaudePath(stub.path) {
            let summarizer = try #require(ClaudeCLISummarizer(log: throwawayLog()))
            let error = await #expect(throws: ClaudeCLISummarizer.Failure.self) {
                _ = try await summarizer.summarize(transcript: "x")
            }
            #expect(error?.localizedDescription.contains("Not logged in") == true)
        }
    }

    /// An app started by LaunchServices hands its children a stripped
    /// environment, and `claude` resolves its keychain credentials by the account
    /// name in `USER` — without it, it reports "Not logged in" and exits 1. The
    /// summarizer must supply the essentials rather than inherit whatever it got.
    @Test func spawnsChildWithUSEREvenWhenTheAppDidNotInheritOne() async throws {
        let stub = try makeStub(
            """
            #!/bin/sh
            cat > /dev/null
            if [ -z "$USER" ]; then echo 'no USER in environment'; exit 1; fi
            printf '## Summary\\nStub summary.\\n'
            """)
        defer { try? FileManager.default.removeItem(at: stub.deletingLastPathComponent()) }

        try await withCLaudePath(stub.path) {
            try await withoutEnv("USER") {
                let summarizer = try #require(ClaudeCLISummarizer(log: throwawayLog()))
                let result = try await summarizer.summarize(transcript: "x")
                #expect(result.markdown.contains("Stub summary."))
            }
        }
    }

    /// A failure must leave a record that outlives the UI banner — and must not
    /// drag call content into it. The positive assertion comes first on purpose:
    /// "the sentinel is absent" passes vacuously against a log that was never
    /// written, so it only means something once the ERROR line is proven present.
    @Test func logsTheFailureWithoutLeakingTranscriptContent() async throws {
        let stub = try makeStub(
            """
            #!/bin/sh
            cat > /dev/null
            echo 'Not logged in · Please run /login'
            exit 1
            """)
        defer { try? FileManager.default.removeItem(at: stub.deletingLastPathComponent()) }
        let logDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("summarizer-log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: logDir) }
        let log = Log(directory: logDir)

        let sentinel = "ОБОРОТ-СЕНТИНЕЛЬ-42"
        try await withCLaudePath(stub.path) {
            let summarizer = try #require(ClaudeCLISummarizer(log: log))
            await #expect(throws: ClaudeCLISummarizer.Failure.self) {
                _ = try await summarizer.summarize(
                    transcript: "**[00:00:00] Speaker 1:** \(sentinel)")
            }
        }

        let contents = try String(contentsOf: log.fileURL, encoding: .utf8)
        #expect(contents.contains("ERROR"))
        #expect(contents.contains("exit=1"))
        #expect(contents.contains(sentinel) == false)
    }

    /// The timeout must actually fire. `readDataToEndOfFile()` blocks until the
    /// child exits, so a deadline checked only afterwards can never be reached —
    /// a hung `claude` would leave the app waiting forever with the stage logged
    /// as started and no result, which is indistinguishable from a silent failure.
    @Test func hungChildHitsTheTimeoutInsteadOfBlockingForever() async throws {
        let stub = try makeStub(
            """
            #!/bin/sh
            cat > /dev/null
            sleep 30
            echo 'too late'
            """)
        defer { try? FileManager.default.removeItem(at: stub.deletingLastPathComponent()) }

        try await withCLaudePath(stub.path) {
            let summarizer = try #require(
                ClaudeCLISummarizer(timeout: 1, log: throwawayLog()))
            let started = Date()
            await #expect(throws: ClaudeCLISummarizer.Failure.self) {
                _ = try await summarizer.summarize(transcript: "x")
            }
            // Must give up on its own deadline, not wait out the child's 30s.
            #expect(Date().timeIntervalSince(started) < 10)
        }
    }

    /// Write `script` as an executable `claude` stub in a fresh temp directory.
    private func makeStub(_ script: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-stub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stub = dir.appendingPathComponent("claude")
        try script.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        return stub
    }
}

/// Run `body` with `key` removed from the environment, restoring it afterwards —
/// stands in for the stripped environment of a GUI-launched app.
private func withoutEnv(_ key: String, _ body: () async throws -> Void) async throws {
    let previous = ProcessInfo.processInfo.environment[key]
    unsetenv(key)
    defer { previous.map { setenv(key, $0, 1) } ?? unsetenv(key) }
    try await body()
}

/// A Log pointed at a throwaway directory. Tests must never write to
/// `Log.shared`, which is the user's real `~/Library/Logs/CallScribe` file.
private func throwawayLog() -> Log {
    Log(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("test-log-\(UUID().uuidString)"))
}

/// Run `body` with CALLSCRIBE_CLAUDE_PATH set, restoring it afterwards.
private func withCLaudePath(_ path: String, _ body: () async throws -> Void) async throws {
    let key = "CALLSCRIBE_CLAUDE_PATH"
    let previous = ProcessInfo.processInfo.environment[key]
    setenv(key, path, 1)
    defer { previous.map { setenv(key, $0, 1) } ?? unsetenv(key) }
    try await body()
}
