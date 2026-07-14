import Foundation

/// One recognized word on the shared session timeline (both tracks start at
/// the session clock's zero, so their word times compare directly).
public struct Word: Sendable, Codable, Equatable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let probability: Float

    public init(text: String, start: TimeInterval, end: TimeInterval, probability: Float = 1.0) {
        self.text = text
        self.start = start
        self.end = end
        self.probability = probability
    }
}

public struct AttributedWord: Sendable, Equatable {
    public let word: Word
    public let speaker: Speaker

    public init(word: Word, speaker: Speaker) {
        self.word = word
        self.speaker = speaker
    }
}

/// A run of consecutive words by one speaker.
public struct Utterance: Sendable, Codable, Equatable {
    public let speaker: Speaker
    public let words: [Word]

    public init(speaker: Speaker, words: [Word]) {
        self.speaker = speaker
        self.words = words
    }

    public var start: TimeInterval { words.first?.start ?? 0 }
    public var end: TimeInterval { words.last?.end ?? 0 }

    /// Whisper word tokens carry leading spaces; normalize while joining.
    public var text: String {
        words
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

public struct Transcript: Sendable, Codable, Equatable {
    public let utterances: [Utterance]
    public let detectedLanguage: String?

    public init(utterances: [Utterance], detectedLanguage: String? = nil) {
        self.utterances = utterances
        self.detectedLanguage = detectedLanguage
    }
}
