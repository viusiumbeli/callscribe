import Foundation
import WhisperKit

/// Gets the Whisper model onto disk and *loadable*, once, in the background.
///
/// "Downloaded" is not the same as "usable": `WhisperKit.loadModels` resolves the
/// tokenizer separately from the model snapshot, so an interrupted first run can
/// leave `AudioEncoder.mlmodelc` in place with no tokenizer — and a file-existence
/// check would then claim readiness and hit the network again mid-transcription.
/// Provisioning is therefore download + one successful load (which caches the
/// tokenizer), recorded by a marker file inside the variant folder.
public actor ModelProvisioner {
    public static let shared = ModelProvisioner()

    /// Every provisioning failure — offline, disk, a failed load, an unexpected
    /// download location — surfaces as this one type, so callers can tell "the
    /// model isn't ready yet" apart from a real pipeline error and keep the
    /// recording queued instead of dropping it.
    public enum Failure: LocalizedError {
        case notProvisioned(String)
        case unexpectedModelLocation(downloaded: String, expected: String)

        public var errorDescription: String? {
            switch self {
            case .notProvisioned(let reason):
                "The transcription model isn't ready yet: \(reason)"
            case .unexpectedModelLocation(let downloaded, let expected):
                "WhisperKit downloaded the model to \(downloaded) but it is loaded from \(expected)."
            }
        }
    }

    private static let markerName = ".callscribe-provisioned"

    /// Where WhisperKit's Hub layout puts `model` under `modelsDir`. The one
    /// definition of that path — `WhisperTranscriber` loads from here too.
    public static func whisperModelURL(
        modelsDir: URL,
        model: String = WhisperTranscriber.defaultModel
    ) -> URL {
        modelsDir.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(model)")
    }

    /// Downloaded *and* loaded at least once. Static and free of actor state so
    /// the UI can seed itself synchronously at launch without an `await`.
    public static func isWhisperReady(
        modelsDir: URL,
        model: String = WhisperTranscriber.defaultModel
    ) -> Bool {
        FileManager.default.fileExists(atPath: markerURL(modelsDir: modelsDir, model: model).path)
    }

    private static func markerURL(modelsDir: URL, model: String) -> URL {
        whisperModelURL(modelsDir: modelsDir, model: model).appendingPathComponent(markerName)
    }

    /// The model files themselves, tokenizer aside — the "does it still need
    /// downloading at all" precondition.
    private static func isDownloaded(modelsDir: URL, model: String) -> Bool {
        FileManager.default.fileExists(
            atPath: whisperModelURL(modelsDir: modelsDir, model: model)
                .appendingPathComponent("AudioEncoder.mlmodelc").path)
    }

    private var inFlight: Task<Void, Error>?
    private var progressSink: (@Sendable (Double?) -> Void)?

    /// Make the model usable, downloading it if needed. Idempotent — concurrent
    /// callers join the single in-flight attempt rather than starting their own.
    ///
    /// - Parameters:
    ///   - onStart: fired once, from inside the actor, only when this call has to
    ///     wait on a download. Lets a caller report "waiting" without a
    ///     check-then-act race against the readiness test.
    ///   - onProgress: 0…1, `nil` while the transfer hasn't reported anything yet.
    ///     A single sink, claimed by the first caller that supplies one (the UI);
    ///     everyone else passes nil and just awaits. Fanning out to several
    ///     consumers would only split one download's progress between them.
    public func ensureReady(
        modelsDir: URL,
        model: String = WhisperTranscriber.defaultModel,
        onStart: (@Sendable () -> Void)? = nil,
        onProgress: (@Sendable (Double?) -> Void)? = nil
    ) async throws {
        if Self.isWhisperReady(modelsDir: modelsDir, model: model) { return }
        if progressSink == nil { progressSink = onProgress }
        onStart?()
        let task = inFlight ?? Task { try await self.provision(modelsDir: modelsDir, model: model) }
        inFlight = task
        try await task.value
    }

    /// Download (when missing) → load once → write the marker. The whole body is
    /// wrapped so callers see `Failure` and nothing else.
    private func provision(modelsDir: URL, model: String) async throws {
        // Runs on the actor: clearing here means a retry starts a fresh attempt
        // instead of re-awaiting this task's outcome. Nothing can create a
        // replacement before this runs, since a new task is only made when
        // `inFlight` is nil.
        defer {
            inFlight = nil
            progressSink = nil
        }

        let expected = Self.whisperModelURL(modelsDir: modelsDir, model: model)
        do {
            if !Self.isDownloaded(modelsDir: modelsDir, model: model) {
                let sink = progressSink
                sink?(nil)
                Log.shared.info("provisioning \(model): downloading into \(modelsDir.path)")
                let downloaded = try await WhisperKit.download(
                    variant: model,
                    downloadBase: modelsDir,
                    progressCallback: { progress in
                        let fraction = progress.fractionCompleted
                        sink?(fraction > 0 ? fraction : nil)
                    }
                )
                // `download` resolves the variant folder itself (globbing the repo
                // listing), so trust its answer over a recomputed path: a marker
                // written beside a folder the loader never consults would mean
                // re-downloading 1.5 GB on every launch.
                guard downloaded.standardizedFileURL == expected.standardizedFileURL else {
                    throw Failure.unexpectedModelLocation(
                        downloaded: downloaded.path, expected: expected.path)
                }
            }
            // The second half of provisioning: this resolves and caches the
            // tokenizer, so later loads are genuinely offline.
            _ = try await WhisperTranscriber(model: model, modelFolder: modelsDir)
            try Data().write(to: Self.markerURL(modelsDir: modelsDir, model: model))
            progressSink?(1)
            Log.shared.info("provisioning \(model): ready")
        } catch let failure as Failure {
            Log.shared.error("provisioning \(model) failed: \(Log.truncated(failure.localizedDescription))")
            throw failure
        } catch {
            Log.shared.error("provisioning \(model) failed: \(Log.truncated(error.localizedDescription))")
            throw Failure.notProvisioned(error.localizedDescription)
        }
    }
}
