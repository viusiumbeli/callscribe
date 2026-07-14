import Foundation

/// Streaming 16 kHz mono Int16 RIFF/WAV writer.
///
/// Audio is the source of truth: samples hit the disk continuously, and the
/// RIFF header sizes are re-patched every ~5 seconds of audio so that a crash
/// (even SIGKILL) leaves a playable file that loses at most the header of the
/// final seconds, never the audio itself.
///
/// Not thread-safe — confine each instance to one serial queue.
public final class WAVWriter {
    private let handle: FileHandle
    private let sampleRate: UInt32
    private var dataBytes: UInt32 = 0
    private var bytesSincePatch: UInt32 = 0
    private let patchThresholdBytes: UInt32

    public init(url: URL, sampleRate: UInt32 = 16000) throws {
        self.sampleRate = sampleRate
        // 2 bytes/sample, mono; patch every ~5 s of audio.
        self.patchThresholdBytes = sampleRate * 2 * 5
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        self.handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: Self.header(sampleRate: sampleRate, dataBytes: 0))
    }

    /// Seconds of audio written so far.
    public var duration: TimeInterval {
        TimeInterval(dataBytes) / TimeInterval(sampleRate * 2)
    }

    public func append(_ samples: [Int16]) throws {
        guard !samples.isEmpty else { return }
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        try handle.write(contentsOf: data)
        dataBytes += UInt32(data.count)
        bytesSincePatch += UInt32(data.count)
        if bytesSincePatch >= patchThresholdBytes {
            try patchHeader()
            bytesSincePatch = 0
        }
    }

    public func finalize() throws {
        try patchHeader()
        try handle.close()
    }

    private func patchHeader() throws {
        try handle.seek(toOffset: 4)
        try handle.write(contentsOf: Data(littleEndian: 36 + dataBytes))
        try handle.seek(toOffset: 40)
        try handle.write(contentsOf: Data(littleEndian: dataBytes))
        try handle.seekToEnd()
    }

    static func header(sampleRate: UInt32, dataBytes: UInt32) -> Data {
        let byteRate = sampleRate * 2
        var d = Data(capacity: 44)
        d.append(contentsOf: Array("RIFF".utf8))
        d.append(Data(littleEndian: 36 + dataBytes))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8))
        d.append(Data(littleEndian: UInt32(16)))            // fmt chunk size
        d.append(Data(littleEndian: UInt16(1)))             // PCM
        d.append(Data(littleEndian: UInt16(1)))             // mono
        d.append(Data(littleEndian: sampleRate))
        d.append(Data(littleEndian: byteRate))
        d.append(Data(littleEndian: UInt16(2)))             // block align
        d.append(Data(littleEndian: UInt16(16)))            // bits per sample
        d.append(contentsOf: Array("data".utf8))
        d.append(Data(littleEndian: dataBytes))
        return d
    }
}

private extension Data {
    init(littleEndian value: UInt32) {
        var v = value.littleEndian
        self = Swift.withUnsafeBytes(of: &v) { Data($0) }
    }

    init(littleEndian value: UInt16) {
        var v = value.littleEndian
        self = Swift.withUnsafeBytes(of: &v) { Data($0) }
    }
}
