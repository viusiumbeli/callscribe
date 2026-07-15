import Foundation

/// Contents of `meta.json` in a call folder: call metadata, the speaker-label →
/// real-name mapping, and pipeline stage flags that make processing resumable.
public struct CallMeta: Codable, Sendable, Equatable {
    public struct PipelineState: Codable, Sendable, Equatable {
        public var transcribed = false
        public var diarized = false
        public var merged = false
        public var summarized = false

        public init() {}
    }

    public var startedAt: Date
    public var endedAt: Date?
    public var durationSec: Double?
    /// Short LLM-generated title (from the summarizer); nil until summarized.
    public var title: String?
    /// Whisper language override ("ru"/"en"); nil = auto-detect.
    public var language: String?
    /// Detected language of the call, filled in after transcription.
    public var detectedLanguage: String?
    /// Debug: gap between session start and each track's first audio buffer
    /// (that much silence is prepended to keep both tracks on one timeline).
    public var micStartOffsetSec: Double?
    public var systemStartOffsetSec: Double?
    /// "Speaker 1" → "Misha"; inferred by the Summarizer or set manually.
    public var speakerNames: [String: String]
    public var pipeline: PipelineState
    public var appVersion: String
    public var whisperModel: String?

    public init(startedAt: Date, appVersion: String) {
        self.startedAt = startedAt
        self.speakerNames = [:]
        self.pipeline = PipelineState()
        self.appVersion = appVersion
    }

    public static func load(from url: URL) throws -> CallMeta {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CallMeta.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
