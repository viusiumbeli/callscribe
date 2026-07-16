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
            // Defaults (0.7 / 1.0 / 10) over-segment call audio: on a real 29-min
            // call FluidAudio reported 5 speakers (one real voice split, plus
            // 1–12 s phantoms). Clustering less eagerly and ignoring short blips
            // collapsed that to the 2 real voices. 0.75 sits in a stable band
            // ([0.74, 0.76] all gave 2 here); higher (0.8) over-merged them to 1.
            // (Merge still folds any sub-3 s survivors.)
            let config = DiarizerConfig(
                clusteringThreshold: 0.75,    // was 0.7 — lower = more speakers
                minSpeechDuration: 1.5,       // was 1.0 — ignore sub-1.5 s blips
                minActiveFramesCount: 16.0    // was 10.0
            )
            let manager = DiarizerManager(config: config)
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
