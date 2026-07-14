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

    public init() {}
}
