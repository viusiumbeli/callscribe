import CallScribeCore
import CallScribeEngine
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    /// The recording lifecycle only. Post-recording processing is tracked
    /// separately (see `processing`) so it can run in the background while the
    /// recorder is free to start again.
    enum Phase: Equatable {
        case idle
        case recording(elapsed: TimeInterval)
        case failed(String)
    }

    /// One call being processed in the background (transcribe → … → summarize).
    struct ProcessingJob: Identifiable, Equatable {
        let folder: CallFolder
        var stage: String
        var id: String { AppState.key(folder) }
    }

    /// Stable identity for a call folder. `standardizedFileURL` (not `==` on the
    /// raw URL, nor `.path`) — the recorder builds URLs via `appendingPathComponent`
    /// while the history lists them via `contentsOfDirectory`, which differ by
    /// symlink resolution (/var vs /private/var) and trailing slash.
    nonisolated static func key(_ folder: CallFolder) -> String {
        folder.url.standardizedFileURL.path
    }

    private(set) var phase: Phase = .idle
    /// Calls queued/processing in the background, in FIFO order (serial).
    private(set) var processing: [ProcessingJob] = []
    /// Last background-processing failure, shown as a dismissable banner.
    private(set) var processingError: String?
    private var draining = false
    private(set) var calls: [CallSummary] = []
    private(set) var projects: [Project] = []
    var selectedProjectID: String = "" {
        didSet {
            guard selectedProjectID != oldValue else { return }
            persistProjects()
            refreshHistory()
        }
    }

    private let projectStore = ProjectStore()
    private var session: RecordingSession?
    private var timerTask: Task<Void, Never>?
    private var startedAt: Date?

    var selectedProject: Project {
        projects.first { $0.id == selectedProjectID } ?? projects.first
            ?? ProjectStore.makeDefault()
    }

    /// Storage for the currently-selected project.
    private var store: CallStore { CallStore(rootURL: selectedProject.rootURL) }

    struct CallSummary: Identifiable, Hashable {
        let id: String
        let folder: CallFolder
        let startedAt: Date?
        let durationSec: Double?
        let title: String?
        var name: String { folder.name }
    }

    init() {
        let state = projectStore.load()
        projects = state.projects
        selectedProjectID = state.selectedID
        refreshHistory()
    }

    // MARK: - Projects

    /// Create a project: inside the user-chosen `parentURL`, make a dedicated
    /// folder named after the project — recordings and `claude` live there, so
    /// nothing else in the chosen directory is touched — then switch to it.
    func addProject(name: String, parentURL: URL) {
        let workingDir = parentURL.appendingPathComponent(Project.folderSlug(name), isDirectory: true)
        try? FileManager.default.createDirectory(at: workingDir, withIntermediateDirectories: true)
        let project = Project(id: UUID().uuidString, name: name, path: workingDir.path)
        projects.append(project)
        persistProjects()
        selectedProjectID = project.id   // triggers refreshHistory via didSet
    }

    /// Remove a project from CallScribe (its files on disk are left untouched).
    func removeProject(_ id: String) {
        guard projects.count > 1 else { return }   // always keep at least one
        projects.removeAll { $0.id == id }
        if selectedProjectID == id {
            selectedProjectID = projects.first?.id ?? ""   // didSet persists + refreshes
        } else {
            persistProjects()
        }
    }

    private func persistProjects() {
        try? projectStore.save(.init(projects: projects, selectedID: selectedProjectID))
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
        processing.removeAll { $0.id == Self.key(folder) }   // stop tracking if queued
        try? store.delete(folder)
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
            phase = .idle                 // recorder is free again immediately
            enqueueProcessing(folder)      // pipeline runs in the background
            refreshHistory()               // the new call appears right away
        } catch {
            self.session = nil
            phase = .failed(error.localizedDescription)
        }
    }

    /// Abort the current recording and discard it — stop the session, delete its
    /// folder, and return to idle without transcribing.
    func cancelRecording() {
        guard let session else { return }
        timerTask?.cancel()
        self.session = nil
        _ = try? session.stop()             // close the WAV writers cleanly
        try? store.delete(session.folder)   // discard the whole folder
        phase = .idle
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

    // MARK: - Background processing queue

    /// Is this call currently queued or processing?
    func isProcessing(_ folder: CallFolder) -> Bool {
        processing.contains { $0.id == Self.key(folder) }
    }

    /// Current stage for a processing call (nil if not processing).
    func processingStage(for folder: CallFolder) -> String? {
        processing.first { $0.id == Self.key(folder) }?.stage
    }

    var processingCount: Int { processing.count }

    /// Background jobs whose call lives in the currently-selected project (a call
    /// folder sits directly under its project root).
    var selectedProjectProcessing: [ProcessingJob] {
        let root = selectedProject.rootURL.standardizedFileURL.path
        return processing.filter {
            $0.folder.url.deletingLastPathComponent().standardizedFileURL.path == root
        }
    }

    func clearProcessingError() { processingError = nil }

    private func enqueueProcessing(_ folder: CallFolder) {
        processing.append(ProcessingJob(folder: folder, stage: "queued"))
        drainQueue()
    }

    /// Drain the queue one call at a time — two concurrent transcriptions would
    /// thrash memory/ANE, and recording stays responsive regardless (the heavy
    /// work is inside the PipelineRunner actor).
    private func drainQueue() {
        guard !draining else { return }
        draining = true
        Task {
            while let job = processing.first {
                do {
                    let runner = PipelineRunner(
                        folder: job.folder,
                        modelsDir: try AppPaths.ensureModelsDirectory(),
                        // The call's own project directory (robust to switching).
                        summarizer: ClaudeCLISummarizer(
                            workingDirectory: job.folder.url.deletingLastPathComponent())
                    )
                    try await runner.run { stage in
                        Task { @MainActor in self.setStage(job.id, stage.rawValue) }
                    }
                } catch {
                    processingError = error.localizedDescription
                }
                processing.removeAll { $0.id == job.id }
                refreshHistory()
            }
            draining = false
        }
    }

    private func setStage(_ id: String, _ stage: String) {
        if let i = processing.firstIndex(where: { $0.id == id }) { processing[i].stage = stage }
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

    /// Names of all currently-enrolled voices (for the UI to show "forget").
    func enrolledVoiceNames() -> Set<String> {
        Set(VoiceStore().load().map(\.name))
    }

    /// The saved "number of remote participants" hint for a call (nil = auto).
    func expectedSpeakers(for folder: CallFolder) -> Int? {
        (try? folder.loadMeta())?.expectedSpeakers
    }

    /// Fix how many remote speakers to split into, then re-diarize + re-merge.
    /// Per-call action — throws so the detail view shows a local error.
    func setExpectedSpeakers(_ count: Int?, for folder: CallFolder) async throws {
        var meta = try folder.loadMeta()
        meta.expectedSpeakers = count
        try folder.saveMeta(meta)
        try await reprocessSpeakers(folder, modelsDir: try AppPaths.ensureModelsDirectory())
    }

    /// Learn `label`'s voice from this call under `name`, then re-diarize +
    /// re-merge so it (and future calls) label them by name. Per-call action.
    func enrollVoice(label: String, name: String, in folder: CallFolder) async throws {
        let modelsDir = try AppPaths.ensureModelsDirectory()
        let embedding = try await VoiceEnroller.embedding(
            forSpeakerLabel: label, in: folder, modelDirectory: modelsDir)
        try VoiceStore().upsert(VoiceProfile(name: name, embedding: embedding))
        try await reprocessSpeakers(folder, modelsDir: modelsDir)
    }

    /// Forget a learned voice, then re-diarize + re-merge this call.
    func forgetVoice(name: String, in folder: CallFolder) async throws {
        try VoiceStore().removeVoice(named: name)
        try await reprocessSpeakers(folder, modelsDir: try AppPaths.ensureModelsDirectory())
    }

    /// Re-run diarize + merge (transcription is cached, so this is fast-ish).
    private func reprocessSpeakers(_ folder: CallFolder, modelsDir: URL) async throws {
        let runner = PipelineRunner(folder: folder, modelsDir: modelsDir, summarizer: nil)
        _ = try await runner.runStage(.diarize, force: true)
        _ = try await runner.runStage(.merge, force: true)
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
