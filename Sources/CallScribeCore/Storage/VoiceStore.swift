import Foundation

/// Persists learned voices (`VoiceProfile`) in a small JSON file under
/// Application Support. One global library shared across projects — enroll a
/// person once and every future call can recognise them.
public final class VoiceStore {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = base.appendingPathComponent("CallScribe/voices.json")
        }
    }

    public func load() -> [VoiceProfile] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let voices = try? decoder.decode([VoiceProfile].self, from: data)
        else { return [] }
        return voices
    }

    public func save(_ voices: [VoiceProfile]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(voices).write(to: fileURL, options: .atomic)
    }

    /// Add or replace a voice, matching by case-insensitive name (re-enrolling a
    /// person updates their fingerprint rather than duplicating them).
    @discardableResult
    public func upsert(_ voice: VoiceProfile) throws -> [VoiceProfile] {
        var voices = load()
        if let i = voices.firstIndex(where: { $0.name.caseInsensitiveCompare(voice.name) == .orderedSame }) {
            voices[i] = voice
        } else {
            voices.append(voice)
        }
        try save(voices)
        return voices
    }

    /// Remove the voice with this name (case-insensitive).
    @discardableResult
    public func removeVoice(named name: String) throws -> [VoiceProfile] {
        var voices = load()
        voices.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        try save(voices)
        return voices
    }
}
