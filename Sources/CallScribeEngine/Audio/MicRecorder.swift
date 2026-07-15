import AVFAudio

/// Records the default input device (the user's microphone — the "Me" track)
/// via AVAudioEngine and feeds buffers to a TrackSink.
final class MicRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let sink: TrackSink

    init(sink: TrackSink) {
        self.sink = sink
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
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, when in
            sink.enqueue(buffer, hostTime: when.hostTime)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
