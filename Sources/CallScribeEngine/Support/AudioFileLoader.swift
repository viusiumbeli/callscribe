import AVFoundation
import CallScribeCore

/// Loads a WAV file as 16 kHz mono Float32 samples for the ML engines.
/// Our own recordings are already 16 kHz mono, but fixtures or imported files
/// might not be, so convert defensively.
enum AudioFileLoader {
    static func loadMono16k(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatUnsupported("cannot build 16 kHz mono float format")
        }

        let sourceFormat = file.processingFormat
        guard let converter = AVAudioConverter(from: sourceFormat, to: target) else {
            throw AudioCaptureError.formatUnsupported("no converter from \(sourceFormat)")
        }

        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let inBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            return []
        }
        try file.read(into: inBuffer)

        let outCapacity = AVAudioFrameCount(Double(frameCount) * 16000 / sourceFormat.sampleRate) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCapacity) else {
            throw AudioCaptureError.formatUnsupported("cannot allocate output buffer")
        }

        var supplied = false
        var convError: NSError?
        let boxed = UncheckedSendable(value: inBuffer)
        nonisolated(unsafe) var served = supplied
        _ = converter.convert(to: outBuffer, error: &convError) { _, status in
            if served { status.pointee = .endOfStream; return nil }
            served = true
            supplied = true
            status.pointee = .haveData
            return boxed.value
        }
        if let convError { throw convError }

        guard outBuffer.frameLength > 0, let channel = outBuffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(outBuffer.frameLength)))
    }
}
