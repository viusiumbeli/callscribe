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
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureError.formatUnsupported("microphone input format unavailable")
        }
        let sink = self.sink
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            sink.enqueue(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
