import Foundation

/// A learned voice "fingerprint": a name plus the 256-float speaker embedding
/// FluidAudio produces. Stored in the voice library so future calls can label
/// this person automatically instead of "Speaker N".
public struct VoiceProfile: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var embedding: [Float]
    public var createdAt: Date

    public init(id: String = UUID().uuidString, name: String, embedding: [Float], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.embedding = embedding
        self.createdAt = createdAt
    }
}
