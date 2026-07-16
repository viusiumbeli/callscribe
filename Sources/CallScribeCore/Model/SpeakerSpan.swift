import Foundation

/// A diarization cluster: "voice `speakerID` was active from `start` to `end`
/// on the system-audio track". Engine-agnostic — the FluidAudio adapter maps
/// its output into these.
public struct SpeakerSpan: Sendable, Codable, Equatable {
    public let speakerID: String
    public let start: TimeInterval
    public let end: TimeInterval
    /// Set when `speakerID` matched an enrolled voice — the person's name, which
    /// the merge turns into a `.named` speaker. nil for anonymous clusters.
    public let name: String?

    public init(speakerID: String, start: TimeInterval, end: TimeInterval, name: String? = nil) {
        self.speakerID = speakerID
        self.start = start
        self.end = end
        self.name = name
    }

    // Tolerant decode: `name` is absent in diarization.json from older builds.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speakerID = try c.decode(String.self, forKey: .speakerID)
        start = try c.decode(TimeInterval.self, forKey: .start)
        end = try c.decode(TimeInterval.self, forKey: .end)
        name = try c.decodeIfPresent(String.self, forKey: .name)
    }
}
