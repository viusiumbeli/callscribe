import Foundation

/// A diarization cluster: "voice `speakerID` was active from `start` to `end`
/// on the system-audio track". Engine-agnostic — the FluidAudio adapter maps
/// its output into these.
public struct SpeakerSpan: Sendable, Codable, Equatable {
    public let speakerID: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(speakerID: String, start: TimeInterval, end: TimeInterval) {
        self.speakerID = speakerID
        self.start = start
        self.end = end
    }
}
