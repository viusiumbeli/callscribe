import CallScribeCore
import Foundation
import WhisperKit

/// Word-timestamped Whisper output for one track, engine-agnostic.
public struct TrackTranscription: Codable, Sendable {
    public let words: [Word]
    public let detectedLanguage: String?
}

/// Wraps WhisperKit for batch transcription of a WAV file. Reuses one loaded
/// model across both tracks (they run serially to bound peak memory).
public final class WhisperTranscriber {
    public static let defaultModel = "openai_whisper-large-v3-v20240930_turbo"

    private let whisperKit: WhisperKit

    public init(
        model: String = defaultModel,
        modelFolder: URL,
        prewarm: Bool = false,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        // If the model is already downloaded, load it straight from disk with no
        // network — transcription is meant to be fully offline, and a Hugging
        // Face hiccup (e.g. a 504) must not break an already-provisioned app.
        // The tokenizer resolves locally too via downloadBase. Fall back to
        // downloading only when the model isn't present yet (first run).
        let localModel = modelFolder
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(model)")
        let isCached = FileManager.default.fileExists(
            atPath: localModel.appendingPathComponent("AudioEncoder.mlmodelc").path)

        let config: WhisperKitConfig
        if isCached {
            config = WhisperKitConfig(
                downloadBase: modelFolder,
                modelFolder: localModel.path,
                verbose: false,
                logLevel: .error,
                prewarm: prewarm,
                load: true,
                download: false
            )
        } else {
            config = WhisperKitConfig(
                model: model,
                downloadBase: modelFolder,
                verbose: false,
                logLevel: .error,
                prewarm: prewarm,
                load: true,
                download: true
            )
        }
        self.whisperKit = try await WhisperKit(config)
    }

    /// Transcribe a WAV file. `language` nil = auto-detect.
    public func transcribe(wav url: URL, language: String?) async throws -> TrackTranscription {
        let options = DecodingOptions(
            verbose: false,
            language: language,
            detectLanguage: language == nil,
            wordTimestamps: true
        )
        let results = try await whisperKit.transcribe(audioPath: url.path, decodeOptions: options)

        var words: [Word] = []
        for segment in results.flatMap(\.segments) {
            for timing in segment.words ?? [] {
                let text = timing.word.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                words.append(Word(
                    text: timing.word,
                    start: TimeInterval(timing.start),
                    end: TimeInterval(timing.end),
                    probability: timing.probability
                ))
            }
        }
        return TrackTranscription(words: words, detectedLanguage: results.first?.language)
    }
}
