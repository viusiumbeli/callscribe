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
            let summarizer = try #require(ClaudeCLISummarizer())
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
            let summarizer = try #require(ClaudeCLISummarizer())
            await #expect(throws: ClaudeCLISummarizer.Failure.self) {
                _ = try await summarizer.summarize(transcript: "x")
            }
        }
    }
}

/// Run `body` with CALLSCRIBE_CLAUDE_PATH set, restoring it afterwards.
private func withCLaudePath(_ path: String, _ body: () async throws -> Void) async throws {
    let key = "CALLSCRIBE_CLAUDE_PATH"
    let previous = ProcessInfo.processInfo.environment[key]
    setenv(key, path, 1)
    defer { previous.map { setenv(key, $0, 1) } ?? unsetenv(key) }
    try await body()
}
