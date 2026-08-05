import CallScribeCore
import Foundation
import Testing
@testable import CallScribeEngine

/// The two pipeline stages that swallow their failures by design used to leave no
/// trace at all — a call could come out transcribed from un-cancelled audio, or
/// with every remote speaker merged into one, and nothing recorded why.
@Suite struct PipelineRunnerLoggingTests {
    /// A call folder with meta.json but no audio, so `EchoCanceller.process`
    /// returns false ("missing/empty inputs") and the stage is skipped.
    private func makeCallWithoutAudio() throws -> CallFolder {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("runner-log-\(UUID().uuidString)")
        let folder = CallFolder(url: root)
        try FileManager.default.createDirectory(at: folder.cacheDir, withIntermediateDirectories: true)
        let meta = CallMeta(startedAt: Date(timeIntervalSince1970: 1_790_000_000), appVersion: "test")
        try folder.saveMeta(meta)
        return folder
    }

    @Test func warnsWhenEchoCancellationIsSkipped() async throws {
        let folder = try makeCallWithoutAudio()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let logDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("runner-logdir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: logDir) }
        let log = Log(directory: logDir)

        let runner = PipelineRunner(
            folder: folder, modelsDir: logDir, summarizer: nil, log: log,
            project: "Work calls")
        _ = try await runner.runStage(.echoCancel, force: true)

        let contents = try String(contentsOf: log.fileURL, encoding: .utf8)
        #expect(contents.contains("WARN"))
        #expect(contents.contains("echoCancel"))
        // Names the call it belongs to, so one grep isolates a call's history.
        #expect(contents.contains(folder.name))
        // …and the project, since a folder name is only a timestamp and several
        // projects can hold calls recorded at the same minute.
        #expect(contents.contains("[Work calls]"))
    }

    /// The CLI knows nothing about projects, so it falls back to the containing
    /// directory rather than logging a call with no context at all.
    @Test func fallsBackToTheContainingDirectoryWhenNoProjectIsGiven() async throws {
        let folder = try makeCallWithoutAudio()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let logDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("runner-logdir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: logDir) }
        let log = Log(directory: logDir)
        let parent = folder.url.deletingLastPathComponent().lastPathComponent

        let runner = PipelineRunner(folder: folder, modelsDir: logDir, summarizer: nil, log: log)
        _ = try await runner.runStage(.echoCancel, force: true)

        let contents = try String(contentsOf: log.fileURL, encoding: .utf8)
        #expect(contents.contains("[\(parent)]"))
    }
}
