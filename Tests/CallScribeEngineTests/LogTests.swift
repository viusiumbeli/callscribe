import Foundation
import Testing
@testable import CallScribeEngine

@Suite struct LogTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func read(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @Test func writesOneLinePerEventTaggedWithItsLevel() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = Log(directory: dir)

        log.info("pipeline 2026-08-05_11-31-2 stage=transcribe")
        log.error("pipeline 2026-08-05_11-31-2 stage=summarize: claude exited with code 1")

        let lines = read(log.fileURL).split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0].contains("INFO") && lines[0].contains("stage=transcribe"))
        #expect(lines[1].contains("ERROR") && lines[1].contains("code 1"))
        // The whole point of a fixed-width level: grepping for failures works.
        #expect(lines.filter { $0.contains("ERROR") }.count == 1)
    }

    /// Rotation must not lose the lines it exists to preserve: a retained
    /// FileHandle follows the inode, so renaming while holding it would send
    /// everything afterwards into the rotated-away file.
    @Test func rotatesPastTheCapAndKeepsWritingToTheCurrentFile() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = Log(directory: dir, maxBytes: 200)

        for i in 0..<20 { log.info("filler line number \(i) padded out to force rotation") }
        log.error("after rotation")

        let current = read(log.fileURL)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("callscribe.log.1").path))
        #expect(current.contains("after rotation"))
        #expect(current.utf8.count < 400)
    }
}
