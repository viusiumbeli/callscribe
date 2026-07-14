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
        let system = attribute(
            systemWords: normalize(systemWords, config: config),
            spans: spans,
            config: config
        )

        // Build utterances per track *before* interleaving, so simultaneous
        // speech (cross-talk) yields two overlapping utterances instead of
        // shredding into alternating single words.
        let interleaved = (utterances(from: mic, config: config)
            + utterances(from: system, config: config))
            .sorted { a, b in
                if a.start != b.start { return a.start < b.start }
                if (a.speaker == .me) != (b.speaker == .me) { return a.speaker == .me }
                return (a.end - a.start) > (b.end - b.start)
            }

        return Transcript(
            utterances: coalesce(interleaved, config: config),
            detectedLanguage: detectedLanguage
        )
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
}
