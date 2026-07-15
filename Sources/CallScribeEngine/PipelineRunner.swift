import CallScribeCore
import Foundation

/// Runs the post-recording pipeline: transcribe both tracks → diarize the
/// system track → merge → summarize. Resumable via meta.json stage flags and
/// the `.cache` artifacts, so a crash or a missing `claude` never forces
/// starting over — and never loses the transcript.
public actor PipelineRunner {
    public enum Stage: String, Sendable {
        case transcribe, diarize, merge, summarize
    }

    private let folder: CallFolder
    private let modelsDir: URL
    private let summarizer: Summarizer?
    private let whisperModel: String

    public init(
        folder: CallFolder,
        modelsDir: URL,
        summarizer: Summarizer?,
        whisperModel: String = WhisperTranscriber.defaultModel
    ) {
        self.folder = folder
        self.modelsDir = modelsDir
        self.summarizer = summarizer
        self.whisperModel = whisperModel
    }

    /// Run every stage that hasn't completed yet.
    /// `onStage` reports progress for the UI.
    @discardableResult
    public func run(
        force: Bool = false,
        onStage: (@Sendable (Stage) -> Void)? = nil
    ) async throws -> CallMeta {
        try FileManager.default.createDirectory(at: folder.cacheDir, withIntermediateDirectories: true)
        var meta = try folder.loadMeta()

        // 1. Transcribe both tracks (serially, one model instance).
        if force || !meta.pipeline.transcribed {
            onStage?(.transcribe)
            let transcriber = try await WhisperTranscriber(model: whisperModel, modelFolder: modelsDir)
            let mic = try await transcriber.transcribe(wav: folder.micWAV, language: meta.language)
            let system = try await transcriber.transcribe(wav: folder.systemWAV, language: meta.language)
            try write(mic, to: folder.whisperMicJSON)
            try write(system, to: folder.whisperSystemJSON)
            meta.detectedLanguage = mic.detectedLanguage ?? system.detectedLanguage
            meta.whisperModel = whisperModel
            meta.pipeline.transcribed = true
            try folder.saveMeta(meta)
        }

        // 2. Diarize the system track (failure → empty spans, never fatal).
        if force || !meta.pipeline.diarized {
            onStage?(.diarize)
            let spans = await FluidDiarizer.diarize(wav: folder.systemWAV, modelDirectory: modelsDir)
            try write(spans, to: folder.diarizationJSON)
            meta.pipeline.diarized = true
            try folder.saveMeta(meta)
        }

        // 3. Merge into transcript.md.
        if force || !meta.pipeline.merged {
            onStage?(.merge)
            try renderTranscript(names: meta.speakerNames)
            meta.pipeline.merged = true
            try folder.saveMeta(meta)
        }

        // 4. Summarize (optional; failure leaves transcript intact).
        if let summarizer, force || !meta.pipeline.summarized {
            onStage?(.summarize)
            let transcript = try String(contentsOf: folder.transcriptMD, encoding: .utf8)
            let result = try await summarizer.summarize(transcript: transcript)
            try result.markdown.write(to: folder.summaryMD, atomically: true, encoding: .utf8)
            if let title = result.title { meta.title = title }
            if !result.speakerNames.isEmpty {
                meta.speakerNames.merge(result.speakerNames) { _, new in new }
                try renderTranscript(names: meta.speakerNames)  // re-render with names
            }
            meta.pipeline.summarized = true
            try folder.saveMeta(meta)
        }

        return meta
    }

    /// Run a single stage in isolation (used by the per-stage CLI subcommands).
    /// Stages depend on their predecessors' `.cache` artifacts existing.
    @discardableResult
    public func runStage(_ stage: Stage, force: Bool) async throws -> CallMeta {
        try FileManager.default.createDirectory(at: folder.cacheDir, withIntermediateDirectories: true)
        var meta = try folder.loadMeta()
        switch stage {
        case .transcribe:
            let transcriber = try await WhisperTranscriber(model: whisperModel, modelFolder: modelsDir)
            let mic = try await transcriber.transcribe(wav: folder.micWAV, language: meta.language)
            let system = try await transcriber.transcribe(wav: folder.systemWAV, language: meta.language)
            try write(mic, to: folder.whisperMicJSON)
            try write(system, to: folder.whisperSystemJSON)
            meta.detectedLanguage = mic.detectedLanguage ?? system.detectedLanguage
            meta.whisperModel = whisperModel
            meta.pipeline.transcribed = true
        case .diarize:
            let spans = await FluidDiarizer.diarize(wav: folder.systemWAV, modelDirectory: modelsDir)
            try write(spans, to: folder.diarizationJSON)
            meta.pipeline.diarized = true
        case .merge:
            try renderTranscript(names: meta.speakerNames)
            meta.pipeline.merged = true
        case .summarize:
            guard let summarizer else { return meta }
            let transcript = try String(contentsOf: folder.transcriptMD, encoding: .utf8)
            let result = try await summarizer.summarize(transcript: transcript)
            try result.markdown.write(to: folder.summaryMD, atomically: true, encoding: .utf8)
            if let title = result.title { meta.title = title }
            if !result.speakerNames.isEmpty {
                meta.speakerNames.merge(result.speakerNames) { _, new in new }
                try renderTranscript(names: meta.speakerNames)
            }
            meta.pipeline.summarized = true
        }
        try folder.saveMeta(meta)
        return meta
    }

    /// Re-render transcript.md from cached data with a (possibly updated) name
    /// map — used by "apply inferred names" and manual rename, no re-merge.
    public func renderTranscript(names: [String: String]) throws {
        let mic: TrackTranscription = try read(folder.whisperMicJSON)
        let system: TrackTranscription = try read(folder.whisperSystemJSON)
        let spans: [SpeakerSpan] = (try? read(folder.diarizationJSON)) ?? []
        let transcript = TranscriptMerger.merge(
            micWords: mic.words,
            systemWords: system.words,
            spans: spans,
            detectedLanguage: mic.detectedLanguage ?? system.detectedLanguage
        )
        let markdown = TranscriptMarkdownRenderer.render(transcript, names: names)
        try markdown.write(to: folder.transcriptMD, atomically: true, encoding: .utf8)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    private func read<T: Decodable>(_ url: URL) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}
