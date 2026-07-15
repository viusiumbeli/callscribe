import CSpeexDSP
import CallScribeCore
import Foundation

/// Offline acoustic echo cancellation. The mic (near-end) contains the user's
/// voice plus the remote voice bleeding in through the speakers; the system
/// track is the clean far-end reference. SpeexDSP's adaptive filter subtracts
/// the echo, leaving (mostly) just the local voice — without the muffling of
/// Apple's real-time voice processing. Assumes the tracks are already
/// time-aligned (see RecordingSession lead-in silence).
public enum EchoCanceller {
    private static let frame = 160          // 10 ms at 16 kHz
    private static let filterLength = 3200  // 200 ms echo tail

    /// Write `outWAV` = mic with the system echo removed. Returns false (and
    /// writes nothing) if inputs are missing/empty or the canceller is
    /// unavailable — callers then fall back to the raw mic.
    @discardableResult
    public static func process(micWAV: URL, systemWAV: URL, outWAV: URL) -> Bool {
        guard let micF = try? AudioFileLoader.loadMono16k(micWAV), !micF.isEmpty,
              let sysF = try? AudioFileLoader.loadMono16k(systemWAV), !sysF.isEmpty
        else { return false }

        guard let state = speex_echo_state_init(Int32(frame), Int32(filterLength)) else { return false }
        defer { speex_echo_state_destroy(state) }
        var rate: Int32 = 16000
        _ = speex_echo_ctl(state, SPEEX_ECHO_SET_SAMPLING_RATE, &rate)

        // SpeexDSP works on 16-bit PCM frames. Pad both to a common frame
        // multiple so the last frame is whole.
        let count = max(micF.count, sysF.count)
        let padded = ((count + frame - 1) / frame) * frame
        let mic = toInt16(micF, count: padded)
        let sys = toInt16(sysF, count: padded)
        var out = [Int16](repeating: 0, count: padded)

        mic.withUnsafeBufferPointer { m in
            sys.withUnsafeBufferPointer { s in
                out.withUnsafeMutableBufferPointer { o in
                    var i = 0
                    while i < padded {
                        speex_echo_cancellation(
                            state,
                            m.baseAddress! + i,   // near-end (mic)
                            s.baseAddress! + i,   // far-end reference (system)
                            o.baseAddress! + i
                        )
                        i += frame
                    }
                }
            }
        }

        let trimmed = Array(out.prefix(micF.count))
        do {
            let writer = try WAVWriter(url: outWAV)
            try writer.append(trimmed)
            try writer.finalize()
            return true
        } catch {
            return false
        }
    }

    private static func toInt16(_ samples: [Float], count: Int) -> [Int16] {
        var result = [Int16](repeating: 0, count: count)
        for i in 0..<min(samples.count, count) {
            let v = (samples[i] * 32767).rounded()
            result[i] = Int16(max(-32768, min(32767, v)))
        }
        return result
    }
}
