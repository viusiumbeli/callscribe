import Foundation

/// The heart of the app: fuses word-timestamped Whisper output from the two
/// tracks into one interleaved, speaker-attributed transcript.
///
/// Mic-track words are all "Me" by construction; system-track words are
/// attributed to `Speaker N` by time-overlap with diarization spans. All
/// stages are pure functions over value types.
public enum TranscriptMerger {
    public static func merge(
        micWords: [Word],
        systemWords: [Word],
        spans: [SpeakerSpan],
        config: MergeConfig = MergeConfig(),
        detectedLanguage: String? = nil
    ) -> Transcript {
        let mic = normalize(micWords, config: config)
            .map { AttributedWord(word: $0, speaker: .me) }
        let normSystem = normalize(systemWords, config: config)
        let system = attribute(systemWords: normSystem, spans: spans, config: config)

        // Build utterances per track *before* interleaving, so simultaneous
        // speech (cross-talk) yields two overlapping utterances instead of
        // shredding into alternating single words.
        let micUtterances = utterances(from: mic, config: config)
        let systemUtterances = utterances(from: system, config: config)

        // Strip speaker bleed: drop "Me" utterances that merely echo the remote
        // voice picked up through the speakers around the same time.
        let cleanedMic = config.echoDedup
            ? micUtterances.filter { !isEcho(of: $0, systemWords: normSystem, config: config) }
            : micUtterances

        let interleaved = (cleanedMic + systemUtterances)
            .sorted { a, b in
                if a.start != b.start { return a.start < b.start }
                if (a.speaker == .me) != (b.speaker == .me) { return a.speaker == .me }
                return (a.end - a.start) > (b.end - b.start)
            }

        // Coalesce, fold away phantom (over-segmented) remote speakers, coalesce
        // the pieces that folding made adjacent, then renumber 1..k.
        let coalesced = coalesce(interleaved, config: config)
        let folded = foldPhantomSpeakers(coalesced, config: config)
        let final = renumberRemote(coalesce(folded, config: config))

        return Transcript(utterances: final, detectedLanguage: detectedLanguage)
    }

    // MARK: - Echo dedup

    /// True when `mic` is the remote voice bleeding through the speakers: it
    /// overlaps system-track speech for most of its duration. The echo is
    /// garbled by the time Whisper transcribes it, so we can't match text — but
    /// genuine "Me" speech happens while the remote is silent, so a mic
    /// utterance that sits *on top of* remote speech is echo. `systemWords` must
    /// be sorted by start time.
    static func isEcho(of mic: Utterance, systemWords: [Word], config: MergeConfig) -> Bool {
        let micDuration = max(mic.end - mic.start, 0.001)
        var overlap = 0.0
        for word in systemWords {
            if word.start >= mic.end { break }          // sorted → nothing later overlaps
            let o = min(mic.end, word.end) - max(mic.start, word.start)
            if o > 0 { overlap += o }
        }
        return min(overlap / micDuration, 1.0) >= config.echoOverlapFraction
    }

    // MARK: - Stages

    static func normalize(_ words: [Word], config: MergeConfig) -> [Word] {
        words
            .filter { $0.end > $0.start && $0.probability >= config.minWordProbability }
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    /// Attribute system-track words to `.remote(N)` speakers via diarization
    /// spans. Speakers are numbered by first appearance in time. A word picks
    /// the span with maximum temporal overlap; words outside every span snap
    /// to the nearest span within tolerance, else stick with the previous
    /// word's speaker. No spans at all → everything is `.participant`.
    static func attribute(
        systemWords: [Word],
        spans: [SpeakerSpan],
        config: MergeConfig
    ) -> [AttributedWord] {
        guard !spans.isEmpty else {
            return systemWords.map { AttributedWord(word: $0, speaker: .participant) }
        }

        let sortedSpans = spans.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        var numbering: [String: Int] = [:]
        for span in sortedSpans where numbering[span.speakerID] == nil {
            numbering[span.speakerID] = numbering.count + 1
        }
        func speaker(of span: SpeakerSpan) -> Speaker { .remote(numbering[span.speakerID]!) }

        var result: [AttributedWord] = []
        var previous: Speaker = speaker(of: sortedSpans[0])
        for word in systemWords {
            let best = sortedSpans
                .map { span in (span, overlap: min(word.end, span.end) - max(word.start, span.start)) }
                .max { a, b in a.overlap < b.overlap }!

            let assigned: Speaker
            if best.overlap > 0 {
                assigned = speaker(of: best.0)
            } else {
                // Distance from the word to each span (they don't overlap).
                let nearest = sortedSpans
                    .map { span in (span, distance: max(span.start - word.end, word.start - span.end)) }
                    .min { a, b in a.distance < b.distance }!
                assigned = nearest.distance <= config.spanSnapTolerance
                    ? speaker(of: nearest.0)
                    : previous
            }
            result.append(AttributedWord(word: word, speaker: assigned))
            previous = assigned
        }
        return result
    }

    /// Split one track's attributed words into utterances at speaker changes
    /// and silences longer than `utteranceGap`.
    static func utterances(from words: [AttributedWord], config: MergeConfig) -> [Utterance] {
        var result: [Utterance] = []
        var currentSpeaker: Speaker?
        var currentWords: [Word] = []

        for attributed in words {
            let isBreak = attributed.speaker != currentSpeaker
                || attributed.word.start - (currentWords.last?.end ?? 0) > config.utteranceGap
            if isBreak, let speaker = currentSpeaker, !currentWords.isEmpty {
                result.append(Utterance(speaker: speaker, words: currentWords))
                currentWords = []
            }
            currentSpeaker = attributed.speaker
            currentWords.append(attributed.word)
        }
        if let speaker = currentSpeaker, !currentWords.isEmpty {
            result.append(Utterance(speaker: speaker, words: currentWords))
        }
        return result
    }

    /// Merge adjacent same-speaker utterances separated by less than
    /// `coalesceGap` (repairs splits caused by interleaving).
    static func coalesce(_ utterances: [Utterance], config: MergeConfig) -> [Utterance] {
        var result: [Utterance] = []
        for utterance in utterances {
            if let last = result.last,
               last.speaker == utterance.speaker,
               utterance.start - last.end < config.coalesceGap {
                result[result.count - 1] = Utterance(
                    speaker: last.speaker,
                    words: last.words + utterance.words
                )
            } else {
                result.append(utterance)
            }
        }
        return result
    }

    // MARK: - Phantom speakers

    /// Diarization over-segments: clustering drift spawns short-lived phantom
    /// speaker IDs (e.g. a 1 s "Speaker 5"). Fold every remote speaker whose
    /// total talk-time is below `phantomSpeakerMinDuration` into the nearest
    /// surviving remote speaker by time — keeping the words, just relabeling.
    /// Never removes the last surviving remote speaker (a short call stays put).
    static func foldPhantomSpeakers(_ utterances: [Utterance], config: MergeConfig) -> [Utterance] {
        guard config.phantomSpeakerMinDuration > 0 else { return utterances }

        var total: [Int: TimeInterval] = [:]
        for u in utterances {
            if case .remote(let n) = u.speaker { total[n, default: 0] += u.end - u.start }
        }
        let phantoms = Set(total.filter { $0.value < config.phantomSpeakerMinDuration }.keys)
        let survivors = Set(total.keys).subtracting(phantoms)
        guard !phantoms.isEmpty, !survivors.isEmpty else { return utterances }

        return utterances.map { u in
            guard case .remote(let n) = u.speaker, phantoms.contains(n),
                  let target = nearestSurvivor(to: u, in: utterances, survivors: survivors)
            else { return u }
            return Utterance(speaker: .remote(target), words: u.words)
        }
    }

    /// The surviving remote speaker whose utterances are closest in time to `u`.
    private static func nearestSurvivor(
        to u: Utterance, in all: [Utterance], survivors: Set<Int>
    ) -> Int? {
        var best: (speaker: Int, distance: TimeInterval)?
        for other in all {
            guard case .remote(let n) = other.speaker, survivors.contains(n) else { continue }
            let distance = max(0, max(other.start - u.end, u.start - other.end))
            if best == nil || distance < best!.distance { best = (n, distance) }
        }
        return best?.speaker
    }

    /// Renumber remote speakers 1..k by first appearance, so labels stay
    /// contiguous after folding (no gaps like "Speaker 1, Speaker 4").
    static func renumberRemote(_ utterances: [Utterance]) -> [Utterance] {
        var mapping: [Int: Int] = [:]
        for u in utterances {
            if case .remote(let n) = u.speaker, mapping[n] == nil {
                mapping[n] = mapping.count + 1
            }
        }
        guard mapping.contains(where: { $0.key != $0.value }) else { return utterances }
        return utterances.map { u in
            if case .remote(let n) = u.speaker, let m = mapping[n], m != n {
                return Utterance(speaker: .remote(m), words: u.words)
            }
            return u
        }
    }
}
