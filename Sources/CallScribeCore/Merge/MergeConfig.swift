import Foundation

public struct MergeConfig: Sendable {
    /// Silence inside one track that splits an utterance in two.
    public var utteranceGap: TimeInterval = 1.2
    /// Adjacent same-speaker utterances closer than this are merged back.
    public var coalesceGap: TimeInterval = 0.6
    /// A system-track word outside every diarization span is snapped to the
    /// nearest span within this distance; farther words inherit the previous
    /// word's speaker.
    public var spanSnapTolerance: TimeInterval = 1.0
    /// Words below this Whisper probability are dropped (0 = keep all);
    /// raise to fight hallucinations on silence.
    public var minWordProbability: Float = 0.0

    /// Remove "Me" utterances that are just the remote voice bleeding into the
    /// mic through the speakers. A mic utterance is bleed when most of its words
    /// also appear among the system-track words spoken around the same time.
    /// No-op with headphones (no bleed, so nothing matches).
    public var echoDedup = true
    /// Echo lags the source and the tracks segment differently, so a mic
    /// utterance is matched against system words within this many seconds on
    /// either side of it.
    public var echoTimeTolerance: TimeInterval = 2.0
    /// A mic utterance is bleed when at least this fraction of its (unique) words
    /// appear among those nearby system words.
    public var echoContainment = 0.6
    /// Utterances with fewer words than this are never treated as bleed — keeps
    /// short genuine backchannels ("да", "okay") that happen to echo a word.
    public var echoMinWords = 2

    /// Diarization sometimes invents phantom speakers from clustering drift. A
    /// remote speaker whose total talk-time is below this is folded into the
    /// nearest surviving speaker (never the last one). 0 disables the fold.
    public var phantomSpeakerMinDuration: TimeInterval = 3.0

    public init() {}
}
