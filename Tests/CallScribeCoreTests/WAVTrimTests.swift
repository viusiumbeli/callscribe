import Foundation
import Testing
@testable import CallScribeCore

private func tempWAV() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("wavtrim-test-\(UUID().uuidString).wav")
}

private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
    data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
}

/// A 3 s ramp at 16 kHz: sample i == Int16(i % 30000), so any slice is
/// identifiable byte-for-byte.
private func makeRamp(seconds: Int = 3) throws -> (url: URL, samples: [Int16]) {
    let url = tempWAV()
    let samples = (0..<(16000 * seconds)).map { Int16($0 % 30000) }
    let writer = try WAVWriter(url: url, sampleRate: 16000)
    try writer.append(samples)
    try writer.finalize()
    return (url, samples)
}

/// The Int16 samples of a finalized 44-byte-header WAV.
private func readSamples(_ url: URL) throws -> [Int16] {
    let data = try Data(contentsOf: url)
    let body = data.subdata(in: 44..<data.count)
    return body.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
}

@Test func trimmingTheEndKeepsTheLeadingSamples() throws {
    let (url, samples) = try makeRamp()
    defer { try? FileManager.default.removeItem(at: url) }

    let duration = try WAVTrim.trim(url, from: 0, to: 2)
    #expect(abs(duration - 2.0) < 0.001)
    #expect(try readSamples(url) == Array(samples.prefix(32000)))

    let data = try Data(contentsOf: url)
    #expect(data.count == 44 + 64000)
    #expect(readUInt32LE(data, at: 40) == 64000)        // data chunk size
    #expect(readUInt32LE(data, at: 4) == 36 + 64000)    // RIFF chunk size
    #expect(readUInt32LE(data, at: 24) == 16000)        // sample rate preserved
}

@Test func trimmingTheStartDropsTheLeadingSamples() throws {
    let (url, samples) = try makeRamp()
    defer { try? FileManager.default.removeItem(at: url) }

    let duration = try WAVTrim.trim(url, from: 1, to: 3)
    #expect(abs(duration - 2.0) < 0.001)
    #expect(try readSamples(url) == Array(samples[16000..<48000]))
}

@Test func trimmingBothEndsKeepsTheMiddle() throws {
    let (url, samples) = try makeRamp()
    defer { try? FileManager.default.removeItem(at: url) }

    let duration = try WAVTrim.trim(url, from: 0.5, to: 2.25)
    #expect(abs(duration - 1.75) < 0.001)
    #expect(try readSamples(url) == Array(samples[8000..<36000]))
}

@Test func endBeyondTheRecordingIsClamped() throws {
    let (url, samples) = try makeRamp()
    defer { try? FileManager.default.removeItem(at: url) }

    let duration = try WAVTrim.trim(url, from: 1, to: 999)
    #expect(abs(duration - 2.0) < 0.001)
    #expect(try readSamples(url) == Array(samples[16000...]))
}

@Test func fullRangeLeavesTheFileByteIdentical() throws {
    let (url, _) = try makeRamp()
    defer { try? FileManager.default.removeItem(at: url) }
    let before = try Data(contentsOf: url)

    let duration = try WAVTrim.trim(url, from: 0, to: 3)
    #expect(abs(duration - 3.0) < 0.001)
    #expect(try Data(contentsOf: url) == before)
}

@Test func emptyOrInvertedRangeThrows() throws {
    let (url, _) = try makeRamp()
    defer { try? FileManager.default.removeItem(at: url) }

    #expect(throws: WAVTrimError.emptyRange) { try WAVTrim.trim(url, from: 1, to: 1) }
    #expect(throws: WAVTrimError.emptyRange) { try WAVTrim.trim(url, from: 2, to: 1) }
    // The failed attempts left the audio alone.
    #expect(WAVTrim.duration(of: url) == 3.0)
}

@Test func nonWAVInputThrows() throws {
    let url = tempWAV()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("not audio at all".utf8).write(to: url)

    #expect(throws: (any Error).self) { try WAVTrim.trim(url, from: 0, to: 1) }
    #expect(WAVTrim.duration(of: url) == 0)
}

@Test func durationReadsTheHeader() throws {
    let (url, _) = try makeRamp(seconds: 5)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(WAVTrim.duration(of: url) == 5.0)
}
