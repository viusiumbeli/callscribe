import Foundation
import Testing
@testable import CallScribeCore

private func w(_ text: String, _ start: Double, _ end: Double, p: Float = 1.0) -> Word {
    Word(text: text, start: start, end: end, probability: p)
}

private func span(_ id: String, _ start: Double, _ end: Double) -> SpeakerSpan {
    SpeakerSpan(speakerID: id, start: start, end: end)
}

@Suite struct TranscriptMergerTests {
    @Test func emptyInputsProduceEmptyTranscript() {
        let t = TranscriptMerger.merge(micWords: [], systemWords: [], spans: [])
        #expect(t.utterances.isEmpty)
    }

    @Test func micOnlyIsAllMe() {
        let t = TranscriptMerger.merge(
            micWords: [w("privet", 0, 0.5), w("kak", 0.6, 0.9), w("dela", 1.0, 1.4)],
            systemWords: [],
            spans: []
        )
        #expect(t.utterances.count == 1)
        #expect(t.utterances[0].speaker == .me)
        #expect(t.utterances[0].text == "privet kak dela")
    }

    @Test func micSplitsOnLongSilence() {
        let t = TranscriptMerger.merge(
            micWords: [w("one", 0, 0.5), w("two", 5.0, 5.5)],  // 4.5 s gap
            systemWords: [],
            spans: []
        )
        #expect(t.utterances.count == 2)
        #expect(t.utterances.allSatisfy { $0.speaker == .me })
    }

    @Test func systemWordsAttributedBySpanOverlap() {
        let t = TranscriptMerger.merge(
            micWords: [],
            systemWords: [w("hello", 0.2, 0.6), w("world", 3.1, 3.6)],
            spans: [span("A", 0, 2), span("B", 3, 5)]
        )
        #expect(t.utterances.count == 2)
        #expect(t.utterances[0].speaker == .remote(1))
        #expect(t.utterances[1].speaker == .remote(2))
    }

    @Test func emptySpansFallBackToParticipant() {
        let t = TranscriptMerger.merge(
            micWords: [],
            systemWords: [w("hi", 0, 0.4), w("there", 0.5, 0.9)],
            spans: []
        )
        #expect(t.utterances.count == 1)
        #expect(t.utterances[0].speaker == .participant)
    }

    @Test func wordStraddlingTwoSpansPicksMaxOverlap() {
        // Word [1.8, 2.6]: overlaps span A by 0.2 and span B by 0.6 → B.
        let attributed = TranscriptMerger.attribute(
            systemWords: [w("border", 1.8, 2.6)],
            spans: [span("A", 0, 2), span("B", 2, 4)],
            config: MergeConfig()
        )
        #expect(attributed[0].speaker == .remote(2))
    }

    @Test func wordInGapSnapsToNearestSpanWithinTolerance() {
        // Word [2.2, 2.5] sits in the gap; nearest span is A (distance 0.2 vs 0.5).
        let attributed = TranscriptMerger.attribute(
            systemWords: [w("gap", 2.2, 2.5)],
            spans: [span("A", 0, 2), span("B", 3, 5)],
            config: MergeConfig()
        )
        #expect(attributed[0].speaker == .remote(1))
    }

    @Test func wordFarFromAnySpanSticksWithPreviousSpeaker() {
        var config = MergeConfig()
        config.spanSnapTolerance = 1.0
        let attributed = TranscriptMerger.attribute(
            systemWords: [w("in-b", 3.2, 3.6), w("orphan", 10.0, 10.4)],
            spans: [span("A", 0, 2), span("B", 3, 5)],
            config: config
        )
        #expect(attributed[0].speaker == .remote(2))
        #expect(attributed[1].speaker == .remote(2), "orphan inherits previous word's speaker")
    }

    @Test func speakerChangeMidStreamSplitsUtterance() {
        let t = TranscriptMerger.merge(
            micWords: [],
            systemWords: [w("first", 0.1, 0.5), w("second", 0.6, 1.0), w("reply", 2.2, 2.6)],
            spans: [span("A", 0, 2), span("B", 2, 4)]
        )
        #expect(t.utterances.count == 2)
        #expect(t.utterances[0].speaker == .remote(1))
        #expect(t.utterances[0].text == "first second")
        #expect(t.utterances[1].speaker == .remote(2))
    }

    @Test func longMonologueStaysOneUtterance() {
        let words = (0..<20).map { i in w("w\(i)", Double(i) * 0.5, Double(i) * 0.5 + 0.4) }
        let t = TranscriptMerger.merge(
            micWords: [],
            systemWords: words,
            spans: [span("A", 0, 100)]
        )
        #expect(t.utterances.count == 1)
        #expect(t.utterances[0].words.count == 20)
    }

    @Test func crossTalkKeepsBothUtterancesOrderedByStart() {
        // Me and Speaker 1 talk simultaneously; both survive as whole
        // utterances, mic first on equal start.
        let t = TranscriptMerger.merge(
            micWords: [w("me-a", 1.0, 1.4), w("me-b", 1.5, 1.9)],
            systemWords: [w("them-a", 1.0, 1.4), w("them-b", 1.5, 1.9)],
            spans: [span("A", 0, 3)]
        )
        #expect(t.utterances.count == 2)
        #expect(t.utterances[0].speaker == .me)
        #expect(t.utterances[1].speaker == .remote(1))
        #expect(t.utterances[0].words.count == 2)
        #expect(t.utterances[1].words.count == 2)
    }

    @Test func unsortedInputIsHandled() {
        let t = TranscriptMerger.merge(
            micWords: [w("later", 1.0, 1.4), w("first", 0.0, 0.4)],
            systemWords: [],
            spans: []
        )
        #expect(t.utterances.count == 1)
        #expect(t.utterances[0].text == "first later")
    }

    @Test func lowProbabilityWordsAreFiltered() {
        var config = MergeConfig()
        config.minWordProbability = 0.5
        let t = TranscriptMerger.merge(
            micWords: [w("real", 0, 0.4, p: 0.9), w("ghost", 0.5, 0.9, p: 0.2)],
            systemWords: [],
            spans: [],
            config: config
        )
        #expect(t.utterances.count == 1)
        #expect(t.utterances[0].text == "real")
    }

    @Test func invalidWordsAreDropped() {
        let t = TranscriptMerger.merge(
            micWords: [w("ok", 0, 0.4), w("zero", 1.0, 1.0), w("negative", 3.0, 2.0)],
            systemWords: [],
            spans: []
        )
        #expect(t.utterances.count == 1)
        #expect(t.utterances[0].text == "ok")
    }

    @Test func speakerNumberingFollowsFirstAppearanceInTime() {
        // Diarizer IDs are opaque and arrive unordered; numbering must follow
        // first appearance on the timeline, not ID sort order.
        let t = TranscriptMerger.merge(
            micWords: [],
            systemWords: [w("early", 0.1, 0.5), w("late", 5.1, 5.5)],
            spans: [span("zzz", 0, 2), span("aaa", 5, 7)]
        )
        #expect(t.utterances[0].speaker == .remote(1), "zzz spoke first → Speaker 1")
        #expect(t.utterances[1].speaker == .remote(2))
    }

    @Test func adjacentSameSpeakerUtterancesCoalesce() {
        // Interleaving can split a monologue around a short interjection
        // window; same-speaker pieces within coalesceGap merge back.
        let pieces = [
            Utterance(speaker: .me, words: [w("a", 0, 0.4)]),
            Utterance(speaker: .me, words: [w("b", 0.5, 0.9)]),
            Utterance(speaker: .remote(1), words: [w("c", 3.0, 3.4)]),
        ]
        let merged = TranscriptMerger.coalesce(pieces, config: MergeConfig())
        #expect(merged.count == 2)
        #expect(merged[0].text == "a b")
    }

    @Test func whisperTokenLeadingSpacesAreNormalized() {
        let u = Utterance(speaker: .me, words: [w(" Hello", 0, 0.3), w(" world", 0.4, 0.7)])
        #expect(u.text == "Hello world")
    }
}

@Suite struct RendererTests {
    @Test func rendersTimecodesAndLabels() {
        let t = Transcript(utterances: [
            Utterance(speaker: .me, words: [w("hi", 754, 754.4)]),
            Utterance(speaker: .remote(2), words: [w("hey", 3725, 3725.5)]),
        ])
        let md = TranscriptMarkdownRenderer.render(t)
        #expect(md.contains("**[00:12:34] Me:** hi"))
        #expect(md.contains("**[01:02:05] Speaker 2:** hey"))
    }

    @Test func nameSubstitutionAppliesAndIsIdempotent() {
        let t = Transcript(utterances: [
            Utterance(speaker: .remote(1), words: [w("hello", 0, 0.5)])
        ])
        let names = ["Speaker 1": "Misha"]
        let md = TranscriptMarkdownRenderer.render(t, names: names)
        #expect(md.contains("**[00:00:00] Misha:** hello"))
        // Re-rendering with the same map yields the same output (renders from
        // the model, not from previously rendered text).
        #expect(TranscriptMarkdownRenderer.render(t, names: names) == md)
    }

    @Test func emptyTranscriptRendersEmpty() {
        #expect(TranscriptMarkdownRenderer.render(Transcript(utterances: [])) == "")
    }
}
