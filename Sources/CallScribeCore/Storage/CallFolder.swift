import Foundation

/// Typed paths inside one call's folder. Pipeline intermediates live in a
/// hidden `.cache/` subfolder — invisible in Finder, keeps stages resumable.
public struct CallFolder: Sendable, Hashable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var name: String { url.lastPathComponent }

    public var micWAV: URL { url.appendingPathComponent("mic.wav") }
    public var systemWAV: URL { url.appendingPathComponent("system.wav") }
    public var transcriptMD: URL { url.appendingPathComponent("transcript.md") }
    public var summaryMD: URL { url.appendingPathComponent("summary.md") }
    public var metaJSON: URL { url.appendingPathComponent("meta.json") }

    public var cacheDir: URL { url.appendingPathComponent(".cache") }
    /// Echo-cancelled mic track (produced by the echoCancel stage); the "Me"
    /// signal with the remote voice removed.
    public var micCleanWAV: URL { cacheDir.appendingPathComponent("mic-clean.wav") }
    public var whisperMicJSON: URL { cacheDir.appendingPathComponent("whisper-mic.json") }
    public var whisperSystemJSON: URL { cacheDir.appendingPathComponent("whisper-system.json") }
    public var diarizationJSON: URL { cacheDir.appendingPathComponent("diarization.json") }
    /// Structured merged transcript (utterances with real start/end times) for
    /// the UI — lets playback highlight track overlapping speech precisely,
    /// which the start-only `transcript.md` can't express.
    public var turnsJSON: URL { cacheDir.appendingPathComponent("turns.json") }

    public func loadMeta() throws -> CallMeta {
        try CallMeta.load(from: metaJSON)
    }

    public func saveMeta(_ meta: CallMeta) throws {
        try meta.save(to: metaJSON)
    }
}
