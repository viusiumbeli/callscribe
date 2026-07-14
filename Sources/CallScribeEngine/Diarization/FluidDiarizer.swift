import CallScribeCore
import FluidAudio
import Foundation

/// Wraps FluidAudio diarization of the system-audio track into engine-agnostic
/// `SpeakerSpan`s. Diarization must never take down the pipeline: any failure
/// is reported as an empty span list so the merge falls back to `Participant`.
public enum FluidDiarizer {
    /// Diarize a 16 kHz mono WAV. Returns time-ranged speaker clusters, or an
    /// empty array if diarization could not run.
    public static func diarize(
        wav url: URL,
        modelDirectory: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async -> [SpeakerSpan] {
        do {
            let samples = try AudioFileLoader.loadMono16k(url)
            guard samples.count >= 16000 else { return [] }  // < 1 s: nothing to cluster

            let models = try await DiarizerModels.downloadIfNeeded(to: modelDirectory)
            let manager = DiarizerManager()
            manager.initialize(models: models)

            let result = try manager.performCompleteDiarization(samples, sampleRate: 16000)
            return result.segments.map {
                SpeakerSpan(
                    speakerID: $0.speakerId,
                    start: TimeInterval($0.startTimeSeconds),
                    end: TimeInterval($0.endTimeSeconds)
                )
            }
        } catch {
            return []
        }
    }
}
