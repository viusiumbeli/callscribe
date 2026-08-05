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
    /// `stage` is nil until the pipeline reports its first one — i.e. still queued.
    struct ProcessingJob: Identifiable, Equatable {
        let folder: CallFolder
        var stage: PipelineRunner.Stage?
        var id: String { AppState.key(folder) }
    }

    /// Whether the transcription model is usable yet. `downloading(nil)` means the
    /// transfer hasn't reported a fraction, so the UI shows an indeterminate bar.
    enum ModelState: Equatable {
        case ready
        case downloading(Double?)
        case failed(String)
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
    /// Jobs held back because the model isn't provisioned yet. Kept out of
    /// `processing` so later recordings aren't stuck behind them, and re-admitted
    /// at the front once the model is ready.
    private var parked: [ProcessingJob] = []
    /// Provisioning state of the transcription model (seeded in `init`).
    private(set) var modelState: ModelState = .ready
    /// Stage of a per-call action in flight, by call — foreground work, shown in
    /// that call's status bar only (see `statusJob(for:)`).
    private var actionStages: [String: PipelineRunner.Stage] = [:]
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

    /// The project a call belongs to, by its own path — not the selected one, since
    /// the queue can still hold calls from a project the user has switched away from.
    private func projectName(of folder: CallFolder) -> String? {
        let root = folder.url.deletingLastPathComponent().standardizedFileURL
        return projects.first { $0.rootURL.standardizedFileURL == root }?.name
    }

    struct CallSummary: Identifiable, Hashable {
        let id: String
        let folder: CallFolder
        let startedAt: Date?
        let durationSec: Double?
        let title: String?
        var name: String { folder.name }
    }

    init() {
        // Marks session boundaries in the log, so a failure can be tied to the
        // build it happened on — the reason today's had no trace at all.
        Log.shared.info("app launched version \(AppInfo.version)")
        let state = projectStore.load()
        projects = state.projects
        selectedProjectID = state.selectedID
        // Checked synchronously: an async seed would flash the download chip on
        // every launch of an already-provisioned install.
        if !ModelProvisioner.isWhisperReady(modelsDir: AppPaths.modelsDirectory) {
            provisionModels()
        }
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
                Log.shared.error("recording: microphone access denied")
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
                Log.shared.info("recording started [\(selectedProject.name)] \(session.folder.name)")
                startTimer()
            } catch {
                phase = .failed(error.localizedDescription)
                Log.shared.error("recording failed to start: \(Log.truncated(error.localizedDescription))")
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
            Log.shared.info("recording stopped [\(projectName(of: folder) ?? "?")] \(folder.name)")
            enqueueProcessing(folder)      // pipeline runs in the background
            refreshHistory()               // the new call appears right away
        } catch {
            self.session = nil
            phase = .failed(error.localizedDescription)
            Log.shared.error("recording failed to stop: \(Log.truncated(error.localizedDescription))")
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
        // The system-audio tap going silent ends the call early — worth finding
        // afterwards, since the recording just stops with no visible reason.
        Log.shared.warn("recording: capture stalled, ending the session early")
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

    /// Everything the UI must treat as in-flight: draining plus parked. Every
    /// reader below goes through this — one that missed `parked` would, for
    /// instance, re-enable trimming on a call whose pipeline is about to resume.
    private var allJobs: [ProcessingJob] { processing + parked }

    /// Is this call queued, processing, or waiting for the model?
    func isProcessing(_ folder: CallFolder) -> Bool {
        allJobs.contains { $0.id == Self.key(folder) }
    }

    /// The in-flight job for this call, if any — its `stage` is nil while queued.
    func processingJob(for folder: CallFolder) -> ProcessingJob? {
        allJobs.first { $0.id == Self.key(folder) }
    }

    var processingCount: Int { allJobs.count }

    /// What a call's status bar should show: its background job if it has one, else
    /// a per-call action in flight. Deliberately separate from `isProcessing` and
    /// `processingCount`, which stay background-only — they gate trimming, the
    /// reload observer and the tray's "Processing N calls…" line, none of which
    /// should react to a foreground action.
    func statusJob(for folder: CallFolder) -> ProcessingJob? {
        if let job = processingJob(for: folder) { return job }
        guard let stage = actionStages[Self.key(folder)] else { return nil }
        return ProcessingJob(folder: folder, stage: stage)
    }

    /// Report `stage` in the call's status bar for as long as a per-call action
    /// runs. A dictionary keyed by call makes "one status per call" structural.
    private func showing<T>(
        _ stage: PipelineRunner.Stage,
        on folder: CallFolder,
        _ body: () async throws -> T
    ) async throws -> T {
        actionStages[Self.key(folder)] = stage
        defer { actionStages[Self.key(folder)] = nil }
        return try await body()
    }

    func clearProcessingError() { processingError = nil }

    private func enqueueProcessing(_ folder: CallFolder) {
        processing.append(ProcessingJob(folder: folder, stage: nil))
        drainQueue()
    }

    /// Drain the queue one call at a time — two concurrent transcriptions would
    /// thrash memory/ANE, and recording stays responsive regardless (the heavy
    /// work is inside the PipelineRunner actor).
    private func drainQueue() {
        admitParked()
        guard !draining else { return }
        draining = true
        Task {
            // `while true` rather than `while let job = processing.first`: a job
            // parked mid-drain empties the queue, and this loop must reconsider
            // re-admission before it exits — nothing re-enters once `draining`
            // goes false except a new recording.
            while true {
                admitParked()
                guard let job = processing.first else { break }
                do {
                    let runner = PipelineRunner(
                        folder: job.folder,
                        modelsDir: try AppPaths.ensureModelsDirectory(),
                        // The call's own project directory (robust to switching).
                        summarizer: ClaudeCLISummarizer(
                            workingDirectory: job.folder.url.deletingLastPathComponent()),
                        project: projectName(of: job.folder)
                    )
                    try await runner.run { stage in
                        Task { @MainActor in self.setStage(job.id, stage) }
                    }
                } catch let failure as ModelProvisioner.Failure {
                    // The audio and meta.json are intact and the pipeline is
                    // resumable, so park the job rather than dropping it, and let
                    // later recordings through while the model is missing.
                    processingError = failure.localizedDescription
                    park(job.id)
                    if case .downloading = modelState {} else { provisionModels() }
                    continue
                } catch {
                    processingError = error.localizedDescription
                    // The runner logs which stage died; this records that the job
                    // is being dropped from the queue rather than retried.
                    Log.shared.error("queue: giving up on [\(projectName(of: job.folder) ?? "?")] \(job.folder.name)")
                }
                processing.removeAll { $0.id == job.id }
                refreshHistory()
            }
            draining = false
        }
    }

    private func setStage(_ id: String, _ stage: PipelineRunner.Stage) {
        if let i = processing.firstIndex(where: { $0.id == id }) { processing[i].stage = stage }
    }

    /// Hold a job aside until the model is provisioned.
    private func park(_ id: String) {
        guard let i = processing.firstIndex(where: { $0.id == id }) else { return }
        var job = processing.remove(at: i)
        job.stage = .waitingForModel   // set explicitly: nil would read "Queued…"
        parked.append(job)
        Log.shared.warn("queue: parked [\(projectName(of: job.folder) ?? "?")] \(job.folder.name) until the model is provisioned")
    }

    /// Re-admit parked jobs, at the front so FIFO order survives. Keyed off actual
    /// readiness rather than who observed it — the model can also be provisioned by
    /// the CLI, or by an attempt this state already gave up on.
    private func admitParked() {
        guard !parked.isEmpty,
              ModelProvisioner.isWhisperReady(modelsDir: AppPaths.modelsDirectory)
        else { return }
        Log.shared.info("queue: re-admitting \(parked.count) parked call(s) — model is ready")
        processing.insert(contentsOf: parked, at: 0)
        parked.removeAll()
    }

    // MARK: - Model provisioning

    /// Download and first-load the transcription model in the background. Safe to
    /// call repeatedly — `ModelProvisioner` coalesces concurrent attempts — so this
    /// doubles as the Retry action.
    func provisionModels() {
        modelState = .downloading(nil)   // never render a retry under a stale error
        Task {
            do {
                let dir = try AppPaths.ensureModelsDirectory()
                try await ModelProvisioner.shared.ensureReady(
                    modelsDir: dir,
                    onProgress: { fraction in
                        Task { @MainActor in self.modelState = .downloading(fraction) }
                    })
                modelState = .ready
                admitParked()
                drainQueue()
            } catch {
                modelState = .failed(error.localizedDescription)
                // ModelProvisioner logs the cause; this records that the UI gave up.
                Log.shared.error("provisioning: reported as failed to the user")
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
            summarizer: nil,
            project: projectName(of: folder)
        )
        try await runner.renderTranscript(names: meta.speakerNames)
        refreshHistory()
    }

    /// Trim this call's audio to `[start, end)` and re-run the whole pipeline in
    /// the background (the trimmed audio invalidates transcript, speakers and
    /// summary alike). Per-call action — throws so the detail view shows a local
    /// error rather than the global recording status.
    func trim(_ folder: CallFolder, from start: TimeInterval, to end: TimeInterval) async throws {
        _ = try CallTrimmer.trim(folder, from: start, to: end)
        enqueueProcessing(folder)
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
        // Loads and compiles the diarizer models before reprocessing even starts.
        let embedding = try await showing(.diarize, on: folder) {
            try await VoiceEnroller.embedding(
                forSpeakerLabel: label, in: folder, modelDirectory: modelsDir)
        }
        try VoiceStore().upsert(VoiceProfile(name: name, embedding: embedding))
        try await reprocessSpeakers(folder, modelsDir: modelsDir)
    }

    /// Forget a learned voice, then re-diarize + re-merge this call.
    func forgetVoice(name: String, in folder: CallFolder) async throws {
        try VoiceStore().removeVoice(named: name)
        try await reprocessSpeakers(folder, modelsDir: try AppPaths.ensureModelsDirectory())
    }

    /// Re-run diarize + merge (transcription is cached, so this is fast-ish).
    /// Reported as two stages, sequentially — one static label would sit on
    /// "Detecting speakers…" through the merge half.
    private func reprocessSpeakers(_ folder: CallFolder, modelsDir: URL) async throws {
        let runner = PipelineRunner(
            folder: folder, modelsDir: modelsDir, summarizer: nil,
            project: projectName(of: folder))
        try await showing(.diarize, on: folder) {
            _ = try await runner.runStage(.diarize, force: true)
        }
        try await showing(.merge, on: folder) {
            _ = try await runner.runStage(.merge, force: true)
        }
        refreshHistory()
    }

    /// Retry just the summary stage. Per-call action — throws so the detail
    /// view shows a local error rather than the global status.
    func retrySummary(for folder: CallFolder) async throws {
        let runner = PipelineRunner(
            folder: folder,
            modelsDir: try AppPaths.ensureModelsDirectory(),
            summarizer: ClaudeCLISummarizer(),
            project: projectName(of: folder)
        )
        try await showing(.summarize, on: folder) {
            _ = try await runner.runStage(.summarize, force: true)
        }
        refreshHistory()
    }
}
