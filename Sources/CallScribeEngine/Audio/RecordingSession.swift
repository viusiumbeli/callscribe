import AppKit
import CallScribeCore
import Foundation

/// Owns a live recording: creates the call folder, checks disk space, starts
/// both tracks on one shared clock, watches for capture stalls, and writes
/// meta.json on stop. Audio is written continuously — a crash keeps whatever
/// reached disk.
public final class RecordingSession: @unchecked Sendable {
    public enum Failure: LocalizedError {
        case insufficientDiskSpace(availableBytes: Int64)

        public var errorDescription: String? {
            switch self {
            case .insufficientDiskSpace(let bytes):
                "Not enough free disk space to record (\(bytes / 1_000_000) MB available)."
            }
        }
    }

    public let folder: CallFolder
    private let appVersion: String
    private let language: String?

    private let micSink: TrackSink
    private let systemSink: TrackSink
    private let micRecorder: MicRecorder
    private let systemRecorder: SystemAudioTapRecorder

    private var meta: CallMeta
    private var stopped = false
    private let onStall: (@Sendable () -> Void)?
    private var watchdog: DispatchSourceTimer?
    private let watchdogQueue = DispatchQueue(label: "callscribe.watchdog")

    public init(
        store: CallStore,
        startedAt: Date,
        appVersion: String,
        language: String? = nil,
        onStall: (@Sendable () -> Void)? = nil
    ) throws {
        let available = try DiskSpace.availableBytes(at: store.rootURL.deletingLastPathComponent())
        guard available >= DiskSpace.minimumBytesForRecording else {
            throw Failure.insufficientDiskSpace(availableBytes: available)
        }

        self.folder = try store.createCallFolder(startedAt: startedAt)
        self.appVersion = appVersion
        self.language = language
        self.onStall = onStall
        // Shared clock zero for both tracks (see TrackSink lead-in silence).
        let sessionStart = mach_absolute_time()
        self.micSink = try TrackSink(url: folder.micWAV, label: "mic", sessionStartHostTime: sessionStart)
        self.systemSink = try TrackSink(url: folder.systemWAV, label: "system", sessionStartHostTime: sessionStart)
        self.micRecorder = MicRecorder(sink: micSink)
        self.systemRecorder = SystemAudioTapRecorder(sink: systemSink)

        self.meta = CallMeta(startedAt: startedAt, appVersion: appVersion)
        self.meta.language = language
        try folder.saveMeta(meta)
    }

    public func start() throws {
        try systemRecorder.start()
        do {
            try micRecorder.start()
        } catch {
            systemRecorder.stop()
            throw error
        }
        startWatchdog()
    }

    @discardableResult
    public func stop() throws -> CallFolder {
        guard !stopped else { return folder }
        stopped = true
        watchdog?.cancel()
        watchdog = nil

        micRecorder.stop()
        systemRecorder.stop()
        try micSink.finish()
        try systemSink.finish()

        meta.endedAt = Date()
        meta.durationSec = max(micSink.duration, systemSink.duration)
        meta.micStartOffsetSec = micSink.startOffsetSec
        meta.systemStartOffsetSec = systemSink.startOffsetSec
        try folder.saveMeta(meta)
        return folder
    }

    /// Fire `onStall` if neither track advances for 5 s (device unplugged,
    /// permission revoked mid-call). The disk files are always preserved.
    private func startWatchdog() {
        var lastMax = 0.0
        var idleTicks = 0
        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let current = max(micSink.duration, systemSink.duration)
            if current > lastMax {
                lastMax = current
                idleTicks = 0
            } else {
                idleTicks += 1
                if idleTicks >= 5 {
                    self.onStall?()
                    timer.cancel()
                }
            }
        }
        timer.resume()
        watchdog = timer
    }
}
