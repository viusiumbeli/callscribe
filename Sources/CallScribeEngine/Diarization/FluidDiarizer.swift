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
        knownVoices: [VoiceProfile] = [],
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

            // Match enrolled voices at the SPEAKER level (not FluidAudio's loose
            // per-segment matching, which over-matches similar voices): average
            // each diarized speaker's segment embeddings and, only if the nearest
            // enrolled voice is within a strict cosine distance, label them.
            let nameBySpeaker = matchVoices(result.segments, to: knownVoices)

            return result.segments.map {
                SpeakerSpan(
                    speakerID: $0.speakerId,
                    start: TimeInterval($0.startTimeSeconds),
                    end: TimeInterval($0.endTimeSeconds),
                    name: nameBySpeaker[$0.speakerId]
                )
            }
        } catch {
            return []
        }
    }

    /// Below this cosine distance between a diarized speaker's centroid and an
    /// enrolled voice we call them the same person. Strict on purpose — a false
    /// name is worse than a missed match.
    static let voiceMatchThreshold: Float = 0.4

    /// Map each diarized `speakerId` to an enrolled voice name, when confident.
    private static func matchVoices(
        _ segments: [TimedSpeakerSegment], to voices: [VoiceProfile]
    ) -> [String: String] {
        guard !voices.isEmpty else { return [:] }

        // Duration-weighted average embedding per diarized speaker.
        var sums: [String: [Float]] = [:]
        for seg in segments where !seg.embedding.isEmpty {
            let weight = max(seg.endTimeSeconds - seg.startTimeSeconds, 0.001)
            var acc = sums[seg.speakerId] ?? [Float](repeating: 0, count: seg.embedding.count)
            for i in seg.embedding.indices { acc[i] += seg.embedding[i] * weight }
            sums[seg.speakerId] = acc
        }

        var result: [String: String] = [:]
        for (speakerId, sum) in sums {
            let centroid = normalize(sum)
            var best: (name: String, distance: Float)?
            for voice in voices {
                let d = cosineDistance(centroid, normalize(voice.embedding))
                if best == nil || d < best!.distance { best = (voice.name, d) }
            }
            if let best, best.distance <= voiceMatchThreshold { result[speakerId] = best.name }
        }
        return result
    }

    private static func normalize(_ v: [Float]) -> [Float] {
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }

    /// 1 − cosine similarity for two L2-normalised vectors (0 = identical).
    private static func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 2 }
        var dot: Float = 0
        for i in a.indices { dot += a[i] * b[i] }
        return 1 - dot
    }
}
