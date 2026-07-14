import ArgumentParser
import CallScribeCore
import CallScribeEngine
import Foundation

struct RecordCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "record",
        abstract: "Record a call to a new folder in ~/Documents/CallNotes."
    )

    @Option(name: .shortAndLong, help: "Stop automatically after N seconds (default: until Ctrl-C).")
    var duration: Double?

    @Option(name: .shortAndLong, help: "Language override: ru or en (default: auto-detect).")
    var language: String?

    func run() async throws {
        guard await PermissionsProbe.requestMicrophoneAccess() else {
            throw AudioCaptureError.microphoneAccessDenied
        }

        let session = try RecordingSession(
            store: CallStore(),
            startedAt: Date(),
            appVersion: AppInfo.version,
            language: language,
            onStall: { print("\n⚠️  capture stalled — stopping; recording so far is kept") }
        )
        try session.start()
        print("● Recording to \(session.folder.url.path)")
        print("  play the call audio; press Ctrl-C to stop.")

        if let duration {
            try await Task.sleep(for: .seconds(duration))
        } else {
            await waitForInterrupt()
        }

        let folder = try session.stop()
        let meta = try folder.loadMeta()
        print("■ Stopped. \(String(format: "%.1f", meta.durationSec ?? 0)) s recorded.")
        print("  Next: callscribe pipeline \(folder.url.path)")
    }

    private func waitForInterrupt() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
            signal(SIGINT, SIG_IGN)
            source.setEventHandler {
                source.cancel()
                continuation.resume()
            }
            source.resume()
        }
    }
}
