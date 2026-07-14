/// A party in the call, as attributed in the final transcript.
public enum Speaker: Hashable, Codable, Sendable {
    /// The local user (microphone track).
    case me
    /// A remote participant identified by diarization, numbered by first appearance.
    case remote(Int)
    /// Fallback when diarization produced no clusters for the system track.
    case participant

    /// Display label before speaker-name substitution.
    public var label: String {
        switch self {
        case .me: "Me"
        case .remote(let n): "Speaker \(n)"
        case .participant: "Participant"
        }
    }
}
