import AVFAudio

/// Converts arbitrary captured audio (any sample rate / channel count / sample
/// format) to 16 kHz mono Int16 — the common denominator for Whisper,
/// FluidAudio, and our WAV files. Stereo is mixed down by AVAudioConverter.
///
/// Not thread-safe — confine to one serial queue.
final class AudioResampler {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    init(inputFormat: AVAudioFormat, outputSampleRate: Double = 16000) throws {
        guard let out = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: outputSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioCaptureError.formatUnsupported("cannot build 16 kHz mono Int16 output format")
        }
        guard let conv = AVAudioConverter(from: inputFormat, to: out) else {
            throw AudioCaptureError.formatUnsupported("no converter from \(inputFormat)")
        }
        self.converter = conv
        self.outputFormat = out
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> [Int16] {
        guard buffer.frameLength > 0 else { return [] }
        return try step(input: buffer, endOfStream: false)
    }

    /// Drain whatever the converter still buffers internally. The converter is
    /// unusable afterwards — call exactly once, when the track ends.
    func flush() throws -> [Int16] {
        try step(input: nil, endOfStream: true)
    }

    private func step(input: AVAudioPCMBuffer?, endOfStream: Bool) throws -> [Int16] {
        let ratio = outputFormat.sampleRate / converter.inputFormat.sampleRate
        let inFrames = input.map { Double($0.frameLength) } ?? 0
        let capacity = max(AVAudioFrameCount(inFrames * ratio) + 64, 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw AudioCaptureError.formatUnsupported("cannot allocate conversion buffer")
        }

        // The input block is typed @Sendable but runs synchronously inside
        // convert(to:error:) on this thread, so the unsafe captures are fine.
        nonisolated(unsafe) var served = false
        let boxedInput = input.map { UncheckedSendable(value: $0) }
        var convError: NSError?
        let status = converter.convert(to: out, error: &convError) { _, outStatus in
            if let boxedInput, !served {
                served = true
                outStatus.pointee = .haveData
                return boxedInput.value
            }
            outStatus.pointee = endOfStream ? .endOfStream : .noDataNow
            return nil
        }
        if status == .error {
            throw convError ?? AudioCaptureError.formatUnsupported("conversion failed")
        }

        guard out.frameLength > 0, let channel = out.int16ChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength)))
    }
}
