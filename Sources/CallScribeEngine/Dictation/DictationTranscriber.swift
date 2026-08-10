import Foundation

/// One Whisper model, kept loaded between dictations. This is the whole reason
/// dictation feels instant.
///
/// The pipeline builds a `WhisperTranscriber` per run and throws it away, which
/// is right for a call: the 5–10 s model load disappears against minutes of
/// work. For dictation it *is* the work, so the instance is held instead.
///
/// It is a second instance, independent of the pipeline's, on purpose: sharing
/// one would park a two-second dictation behind an hour-long call
/// transcription. The cost is both models resident while a call is processing,
/// which `releaseIfIdle(after:)` keeps from becoming the steady state.
///
/// Being an `actor` also gives serialization for free — two dictations can never
/// decode at once.
public actor DictationTranscriber {
    public static let shared = DictationTranscriber()

    private let model: String
    private var transcriber: WhisperTranscriber?
    private var lastUsed: Date?
    private var idleRelease: Task<Void, Never>?

    public init(model: String = WhisperTranscriber.defaultModel) {
        self.model = model
    }

    /// Whether the model is loaded right now — lets the UI say "loading the
    /// model" instead of "transcribing" when the next call will pay for a load.
    public var isWarm: Bool { transcriber != nil }

    /// Load the model if it isn't already. Idempotent, and worth calling the
    /// moment recording *starts* rather than when it ends: the first load then
    /// overlaps the seconds the user spends speaking instead of following them.
    public func prepare(modelsDir: URL) async throws {
        guard transcriber == nil else { return }
        // Surfaces `ModelProvisioner.Failure` when the model isn't downloaded, so
        // the caller can say "still downloading" instead of appearing to hang.
        try await ModelProvisioner.shared.ensureReady(modelsDir: modelsDir, model: model)
        let started = Date()
        transcriber = try await WhisperTranscriber(model: model, modelFolder: modelsDir)
        Log.shared.info(
            "dictation: model loaded in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
    }

    /// Transcribe one utterance to plain text, with the language it turned out to
    /// be in. `text` is "" if the clip held no speech. `language` nil = auto-detect,
    /// in which case the returned one is what Whisper decided.
    public func transcribe(
        wav url: URL,
        language: String?,
        modelsDir: URL
    ) async throws -> (text: String, language: String?) {
        try await prepare(modelsDir: modelsDir)
        guard let transcriber else { return ("", nil) }
        let result = try await transcriber.transcribeText(wav: url, language: language)
        lastUsed = Date()
        guard Self.containsSpeech(result.text) else { return ("", result.language) }
        return (result.text, result.language)
    }

    /// Whisper renders silence as punctuation — a bare "." or "…" — so a hold with
    /// nothing spoken into it comes back non-empty and would paste a stray period
    /// into the user's document. Anything with no letter or digit in it is nothing.
    static func containsSpeech(_ text: String) -> Bool {
        text.contains { $0.isLetter || $0.isNumber }
    }

    /// Drop the model once it has gone unused for `interval`. Rescheduled by each
    /// call, so a burst of dictations keeps it warm and a quiet spell hands the
    /// memory back.
    public func releaseIfIdle(after interval: TimeInterval) {
        idleRelease?.cancel()
        idleRelease = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            await self?.releaseIfUnused(for: interval)
        }
    }

    private func releaseIfUnused(for interval: TimeInterval) async {
        guard let transcriber,
              let lastUsed,
              // Re-checked rather than trusted: the sleep says the timer elapsed,
              // not that nothing used the model in the meantime.
              Date().timeIntervalSince(lastUsed) >= interval
        else { return }
        self.transcriber = nil
        await transcriber.unload()
        Log.shared.info("dictation: released the warm model after \(Int(interval)) s idle")
    }
}
