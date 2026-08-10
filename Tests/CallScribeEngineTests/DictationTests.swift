import Foundation
import Testing
@testable import CallScribeEngine

// MARK: - Dictation log

private func tempLog() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("dictation-test-\(UUID().uuidString)")
        .appendingPathComponent("dictations.md")
}

@Test func theFirstEntryCreatesTheFileWithAHeading() throws {
    let url = tempLog()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    DictationLog(fileURL: url).append("Hello there", at: Date(timeIntervalSince1970: 0))
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(text.hasPrefix("# Dictations\n\n## "))
    #expect(text.contains("Hello there"))
}

@Test func laterEntriesAppendRatherThanReplace() throws {
    let url = tempLog()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let log = DictationLog(fileURL: url)
    log.append("first one")
    log.append("second one")
    log.append("third one")

    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(text.contains("first one"))
    #expect(text.contains("second one"))
    #expect(text.contains("third one"))
    // One heading per entry, and the file's own title.
    #expect(text.components(separatedBy: "## ").count - 1 == 3)
    // Order preserved.
    let first = try #require(text.range(of: "first one"))
    let third = try #require(text.range(of: "third one"))
    #expect(first.lowerBound < third.lowerBound)
}

/// Empty and whitespace-only dictations must not litter the log with headings
/// for nothing — "nothing heard" is a common outcome.
@Test func emptyTextIsNotLogged() {
    let url = tempLog()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let log = DictationLog(fileURL: url)
    log.append("")
    log.append("   \n  ")
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

// The entry *format* is tested in CallScribeCoreTests/DictationLogFormatTests —
// it lives in CallScribeCore so render and parse are verified as a round trip.
// What's left here is the file I/O.

@Test func entriesReadsBackWhatWasAppended() {
    let url = tempLog()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let log = DictationLog(fileURL: url)
    log.append("first one", at: Date(timeIntervalSince1970: 0), language: "en")
    log.append("Раз, два, три", at: Date(timeIntervalSince1970: 60), language: "ru")
    log.append("third one")

    let entries = log.entries()
    #expect(entries.map(\.text) == ["first one", "Раз, два, три", "third one"])
    #expect(entries.map(\.language) == ["en", "ru", nil])
    #expect(entries.map(\.index) == [0, 1, 2])
}

@Test func entriesIsEmptyWhenNothingHasBeenDictated() {
    let url = tempLog()
    #expect(DictationLog(fileURL: url).entries().isEmpty)
}

@Test func removePersistsAndLeavesTheRestReadable() {
    let url = tempLog()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let log = DictationLog(fileURL: url)
    log.append("keep me", at: Date(timeIntervalSince1970: 0))
    log.append("drop me", at: Date(timeIntervalSince1970: 60))
    log.append("keep me too", at: Date(timeIntervalSince1970: 120))

    try? log.remove(index: 1)

    // Re-read from disk, not from memory: the point is that it persisted.
    #expect(DictationLog(fileURL: url).entries().map(\.text) == ["keep me", "keep me too"])

    // And the rewritten file still accepts an append.
    log.append("a later one", at: Date(timeIntervalSince1970: 180))
    #expect(DictationLog(fileURL: url).entries().map(\.text)
        == ["keep me", "keep me too", "a later one"])
}

@Test func removeOnAMissingOrOutOfRangeEntryIsHarmless() {
    let url = tempLog()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let log = DictationLog(fileURL: url)

    // No file at all.
    #expect(throws: Never.self) { try log.remove(index: 0) }
    #expect(!FileManager.default.fileExists(atPath: url.path))

    log.append("only one", at: Date(timeIntervalSince1970: 0))
    try? log.remove(index: 7)
    #expect(log.entries().map(\.text) == ["only one"])
}

// MARK: - Silence rejection

/// Whisper answers a silent clip with punctuation rather than nothing, so
/// "non-empty" is not the same as "heard something".
@Test func punctuationOnlyOutputCountsAsSilence() {
    #expect(!DictationTranscriber.containsSpeech("."))
    #expect(!DictationTranscriber.containsSpeech("..."))
    #expect(!DictationTranscriber.containsSpeech(" … "))
    #expect(!DictationTranscriber.containsSpeech("!?-,"))
    #expect(!DictationTranscriber.containsSpeech(""))
}

@Test func realWordsCountAsSpeech() {
    #expect(DictationTranscriber.containsSpeech("Ship it."))
    #expect(DictationTranscriber.containsSpeech("42"))
    #expect(DictationTranscriber.containsSpeech("Привет."))
}

// MARK: - Plain-text transcription

/// Locks in the dictation decode path against the committed speech fixture.
///
/// Opt-in for the same reason as `GoldenPipelineTests`: it needs the ~1.5 GB
/// model on disk (`callscribe setup`). The assertion is deliberately loose —
/// Whisper's exact wording drifts between model versions, so what matters is
/// that the timestamp-free path returns real words rather than an empty string.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CALLSCRIBE_GOLDEN"] == "1"))
struct DictationTranscriptionTests {
    @Test func plainTextTranscriptionReturnsWords() async throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/golden-call/mic.wav")
        try #require(FileManager.default.fileExists(atPath: fixture.path))

        let (text, language) = try await DictationTranscriber.shared.transcribe(
            wav: fixture, language: nil, modelsDir: try AppPaths.ensureModelsDirectory())

        #expect(!text.isEmpty)
        // Plain text, not the merged transcript format: no timecodes, no speaker
        // labels, and no leading or trailing whitespace to paste into an app.
        #expect(text == text.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(!text.contains("["))
        #expect(!text.contains("  "), "windows should be joined with single spaces")
        // Auto-detect was asked for, so a language must come back — it's what the
        // dictation log records alongside the text.
        #expect(language?.isEmpty == false)
    }
}
