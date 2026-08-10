import AVFAudio

/// Records the default input device (the user's microphone — the "Me" track)
/// via AVAudioEngine and feeds buffers to a TrackSink.
final class MicRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let sink: TrackSink
    private let onLevel: (@Sendable (Float) -> Void)?

    /// - Parameter onLevel: optional 0…1 RMS of each captured buffer, for a live
    ///   level meter. Called on the audio thread, so keep the handler cheap and
    ///   hop to the main actor yourself. Dictation uses it; call recording
    ///   doesn't, and passing nil skips the computation entirely.
    init(sink: TrackSink, onLevel: (@Sendable (Float) -> Void)? = nil) {
        self.sink = sink
        self.onLevel = onLevel
    }

    func start() throws {
        let input = engine.inputNode
        // NB: we deliberately do NOT enable AVAudioEngine voice processing —
        // its telephony-tuned AGC/noise-suppression audibly muffles and quiets
        // the recording. Speaker bleed is removed later at the transcript-merge
        // level (echo dedup) instead, leaving the audio untouched.
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureError.formatUnsupported("microphone input format unavailable")
        }
        let sink = self.sink
        let onLevel = self.onLevel
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, when in
            // Measured before `enqueue`, which takes ownership of the buffer.
            if let onLevel { onLevel(Self.rms(of: buffer)) }
            sink.enqueue(buffer, hostTime: when.hostTime)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// RMS of channel 0, clamped to 0…1. Float taps only — the input node hands
    /// us `pcmFormatFloat32`; anything else reports silence rather than guessing.
    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            sum += channel[i] * channel[i]
        }
        return min(1, (sum / Float(buffer.frameLength)).squareRoot())
    }
}
