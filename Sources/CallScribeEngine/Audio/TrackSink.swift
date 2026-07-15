import AVFAudio
import CallScribeCore
import Foundation

/// Serializes one track's hot path: captured buffers (any format) are
/// resampled to 16 kHz mono and appended to the WAV file, all on a private
/// serial queue. The resampler is created lazily from the first buffer's
/// format, so recorders don't need to know their format up front.
///
/// Alignment: given a shared session-start host time, the first buffer's own
/// host time tells us how late this track began; we prepend that much silence
/// so every track is zero-based at the same instant and the files line up.
final class TrackSink: @unchecked Sendable {
    private static let sampleRate = 16000

    /// IOProc-style producers can be scheduled directly on this queue and call
    /// `processInline` synchronously (zero-copy); everyone else uses `enqueue`.
    let queue: DispatchQueue

    private let writer: WAVWriter
    private let sessionStartHostTime: UInt64
    private var resampler: AudioResampler?
    private var accepting = true
    private var firstError: Error?
    private var prependedLeadIn = false
    private(set) var startOffsetSec: TimeInterval = 0

    init(url: URL, label: String, sessionStartHostTime: UInt64) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.writer = try WAVWriter(url: url)
        self.sessionStartHostTime = sessionStartHostTime
        self.queue = DispatchQueue(label: "callscribe.sink.\(label)")
    }

    /// Hand a buffer over from an arbitrary thread. The caller must not touch
    /// the buffer afterwards — ownership transfers to the sink queue.
    func enqueue(_ buffer: AVAudioPCMBuffer, hostTime: UInt64) {
        let boxed = UncheckedSendable(value: buffer)
        queue.async { self.processInline(boxed.value, hostTime: hostTime) }
    }

    /// Convert + write synchronously. Must run on `queue`.
    func processInline(_ buffer: AVAudioPCMBuffer, hostTime: UInt64) {
        guard accepting, firstError == nil else { return }
        do {
            if !prependedLeadIn {
                prependedLeadIn = true
                prependLeadInSilence(firstBufferHostTime: hostTime)
            }
            if resampler == nil {
                resampler = try AudioResampler(inputFormat: buffer.format)
            }
            try writer.append(resampler!.convert(buffer))
        } catch {
            firstError = error
        }
    }

    /// Pad the start with silence for the gap between the shared session start
    /// and this track's first captured sample, so tracks share a timeline.
    private func prependLeadInSilence(firstBufferHostTime: UInt64) {
        guard firstBufferHostTime > sessionStartHostTime else { return }
        let seconds = Self.hostTicksToSeconds(firstBufferHostTime - sessionStartHostTime)
        guard seconds > 0, seconds < 30 else { return }   // sanity clamp
        startOffsetSec = seconds
        let samples = Int(seconds * Double(Self.sampleRate))
        if samples > 0 {
            try? writer.append([Int16](repeating: 0, count: samples))
        }
    }

    /// Stop accepting, drain the resampler, finalize the WAV header, and
    /// surface the first error the hot path swallowed (if any).
    func finish() throws {
        var result: Result<Void, Error> = .success(())
        queue.sync {
            accepting = false
            do {
                if let tail = try resampler?.flush(), !tail.isEmpty {
                    try writer.append(tail)
                }
                try writer.finalize()
            } catch {
                result = .failure(error)
            }
            if let error = firstError {
                result = .failure(error)
            }
        }
        try result.get()
    }

    var duration: TimeInterval {
        queue.sync { writer.duration }
    }

    // MARK: - Host time

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func hostTicksToSeconds(_ ticks: UInt64) -> TimeInterval {
        Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }
}
