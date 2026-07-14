import AVFAudio
import CallScribeCore
import Foundation

/// Serializes one track's hot path: captured buffers (any format) are
/// resampled to 16 kHz mono and appended to the WAV file, all on a private
/// serial queue. The resampler is created lazily from the first buffer's
/// format, so recorders don't need to know their format up front.
final class TrackSink: @unchecked Sendable {
    /// IOProc-style producers can be scheduled directly on this queue and call
    /// `processInline` synchronously (zero-copy); everyone else uses `enqueue`.
    let queue: DispatchQueue

    private let writer: WAVWriter
    private var resampler: AudioResampler?
    private var accepting = true
    private var firstError: Error?

    init(url: URL, label: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.writer = try WAVWriter(url: url)
        self.queue = DispatchQueue(label: "callscribe.sink.\(label)")
    }

    /// Hand a buffer over from an arbitrary thread. The caller must not touch
    /// the buffer afterwards — ownership transfers to the sink queue.
    func enqueue(_ buffer: AVAudioPCMBuffer) {
        let boxed = UncheckedSendable(value: buffer)
        queue.async { self.processInline(boxed.value) }
    }

    /// Convert + write synchronously. Must run on `queue`.
    func processInline(_ buffer: AVAudioPCMBuffer) {
        guard accepting, firstError == nil else { return }
        do {
            if resampler == nil {
                resampler = try AudioResampler(inputFormat: buffer.format)
            }
            try writer.append(resampler!.convert(buffer))
        } catch {
            firstError = error
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
}
