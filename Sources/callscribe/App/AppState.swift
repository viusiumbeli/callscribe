import CallScribeCore
import CallScribeEngine
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case idle
        case recording(elapsed: TimeInterval)
        case processing(stage: String)
        case done(folder: URL)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var calls: [CallSummary] = []

    private let store = CallStore()
    private var session: RecordingSession?
    private var timerTask: Task<Void, Never>?
    private var startedAt: Date?

    struct CallSummary: Identifiable, Hashable {
        let id: String
        let folder: CallFolder
        let startedAt: Date?
        let durationSec: Double?
        let title: String?
        var name: String { folder.name }
    }

    init() {
        refreshHistory()
    }

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    /// Dismiss a recording-flow error shown in the window.
    func clearError() {
        if case .failed = phase { phase = .idle }
    }

    /// Delete a call's entire folder from disk and drop it from history.
    func delete(_ folder: CallFolder) {
        try? store.delete(folder)
        if case .done(let done) = phase, done == folder.url { phase = .idle }
        refreshHistory()
    }

    func refreshHistory() {
        let folders = (try? store.listCalls()) ?? []
        calls = folders.map { folder in
            let meta = try? folder.loadMeta()
            return CallSummary(
                id: folder.name,
                folder: folder,
                startedAt: meta?.startedAt,
                durationSec: meta?.durationSec,
                title: meta?.title
            )
        }
    }

    func startRecording() {
        guard session == nil else { return }
        Task {
            guard await PermissionsProbe.requestMicrophoneAccess() else {
                phase = .failed("Microphone access denied.")
                return
            }
            do {
                let started = Date()
                let session = try RecordingSession(
                    store: store,
                    startedAt: started,
                    appVersion: AppInfo.version,
                    onStall: { Task { @MainActor in self.handleStall() } }
                )
                try session.start()
                self.session = session
                self.startedAt = started
                self.phase = .recording(elapsed: 0)
                startTimer()
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func stopRecording() {
        guard let session else { return }
        timerTask?.cancel()
        do {
            let folder = try session.stop()
            self.session = nil
            phase = .processing(stage: "starting")
            runPipeline(folder: folder)
        } catch {
            self.session = nil
            phase = .failed(error.localizedDescription)
        }
    }

    private func handleStall() {
        guard isRecording else { return }
        stopRecording()
    }

    private func startTimer() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let started = self.startedAt, self.isRecording else { return }
                self.phase = .recording(elapsed: Date().timeIntervalSince(started))
            }
        }
    }

    private func runPipeline(folder: CallFolder) {
        Task {
            do {
                let modelsDir = try AppPaths.ensureModelsDirectory()
                let runner = PipelineRunner(
                    folder: folder,
                    modelsDir: modelsDir,
                    summarizer: ClaudeCLISummarizer()
                )
                try await runner.run { stage in
                    Task { @MainActor in self.phase = .processing(stage: stage.rawValue) }
                }
                phase = .done(folder: folder.url)
                refreshHistory()
                // "Done" is a brief confirmation, not a resting state — clear it.
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    if case .done(let f) = phase, f == folder.url { phase = .idle }
                }
            } catch {
                phase = .failed(error.localizedDescription)
                refreshHistory()
            }
        }
    }

    /// Rename a speaker label and re-render that call's transcript. Per-call
    /// action — throws so the detail view shows a local error, not the global
    /// recording status.
    func rename(_ label: String, to name: String, in folder: CallFolder) async throws {
        var meta = try folder.loadMeta()
        if name.isEmpty { meta.speakerNames[label] = nil }
        else { meta.speakerNames[label] = name }
        try folder.saveMeta(meta)
        let runner = PipelineRunner(
            folder: folder,
            modelsDir: try AppPaths.ensureModelsDirectory(),
            summarizer: nil
        )
        try await runner.renderTranscript(names: meta.speakerNames)
        refreshHistory()
    }

    /// Retry just the summary stage. Per-call action — throws so the detail
    /// view shows a local error rather than the global status.
    func retrySummary(for folder: CallFolder) async throws {
        let runner = PipelineRunner(
            folder: folder,
            modelsDir: try AppPaths.ensureModelsDirectory(),
            summarizer: ClaudeCLISummarizer()
        )
        _ = try await runner.runStage(.summarize, force: true)
        refreshHistory()
    }
}
