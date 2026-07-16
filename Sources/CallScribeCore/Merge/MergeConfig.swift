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
    /// mic through the speakers. On a speakerphone the mic captures the remote
    /// almost continuously, and Whisper turns that residual echo into
    /// garbled-but-plausible text — so word-matching can't catch it. Instead we
    /// suppress by TIME: mic speech that overlaps remote speech is echo (real
    /// turn-taking speech happens while the remote is silent).
    public var echoDedup = true
    /// A mic ("Me") utterance is treated as echo when at least this fraction of
    /// its duration overlaps system-track speech. With headphones there's little
    /// overlap, so little is dropped.
    public var echoOverlapFraction = 0.6

    /// Diarization sometimes invents phantom speakers from clustering drift. A
    /// remote speaker whose total talk-time is below this is folded into the
    /// nearest surviving speaker (never the last one). 0 disables the fold.
    public var phantomSpeakerMinDuration: TimeInterval = 3.0

    public init() {}
}
