import Foundation

/// Mic-only capture of one short utterance to a WAV file.
///
/// Deliberately *not* `RecordingSession`: dictation wants none of a call's
/// apparatus — no call folder, no `meta.json`, no system-audio tap and its TCC
/// prompt, no 1 GB free-space gate for what is a few seconds of speech. What it
/// does share is the output format, by composing the same two pieces the call
/// recorder uses, so `WhisperTranscriber` reads the result unchanged: 16 kHz
/// mono Int16 WAV via `TrackSink` → `AudioResampler` → `WAVWriter`.
public final class DictationRecorder: @unchecked Sendable {
    private let sink: TrackSink
    private let recorder: MicRecorder
    private var stopped = false

    /// - Parameter onLevel: optional 0…1 input level per buffer, for a meter.
    ///   Called on the audio thread.
    public init(url: URL, onLevel: (@Sendable (Float) -> Void)? = nil) throws {
        // No shared clock to align to, so zero-base on the first sample. Passing
        // "now" instead would prepend the couple of hundred milliseconds the input
        // device takes to spin up as silence, and count it in `duration`.
        self.sink = try TrackSink(url: url, label: "dictation", sessionStartHostTime: nil)
        self.recorder = MicRecorder(sink: sink, onLevel: onLevel)
    }

    public func start() throws {
        try recorder.start()
    }

    /// Stop and finalize the WAV. Returns the seconds captured — the caller uses
    /// it to drop a press too short to hold any speech. Safe to call twice.
    @discardableResult
    public func stop() throws -> TimeInterval {
        guard !stopped else { return sink.duration }
        stopped = true
        recorder.stop()
        try sink.finish()
        return sink.duration
    }
}
