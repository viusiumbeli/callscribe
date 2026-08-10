import ArgumentParser
import CallScribeCore
import CallScribeEngine
import Foundation

/// Dictation's capture→transcribe half, without the hotkey or the paste — so a
/// bad transcription can be told apart from a bad key monitor.
struct DictateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dictate",
        abstract: "Record a few seconds from the mic and print the transcript."
    )

    @Option(name: .shortAndLong, help: "How long to record, in seconds.")
    var seconds: Double = 5

    @Option(name: .shortAndLong, help: "Language override: ru or en (default: auto-detect).")
    var language: String?

    @Flag(help: "Also paste the text into the frontmost app, as the hotkey does.")
    var paste = false

    func run() async throws {
        guard await PermissionsProbe.requestMicrophoneAccess() else {
            throw AudioCaptureError.microphoneAccessDenied
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("callscribe-dictate-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = try DictationRecorder(url: url)
        try recorder.start()
        print("● Listening for \(String(format: "%.0f", seconds)) s — speak now.")
        try await Task.sleep(for: .seconds(seconds))
        let duration = try recorder.stop()
        print("■ Captured \(String(format: "%.1f", duration)) s. Transcribing…")

        let (text, detected) = try await DictationTranscriber.shared.transcribe(
            wav: url,
            language: language,
            modelsDir: try AppPaths.ensureModelsDirectory()
        )
        guard !text.isEmpty else {
            print("(nothing heard)")
            return
        }
        print("\n\(text)\n")
        if let detected { print("language: \(detected)") }

        // Off by default: the bare binary has no bundle identity, so the
        // Accessibility grant it runs under is really the terminal's — which
        // makes a failure here say more about Terminal than about CallScribe.
        guard paste else { return }
        switch await TextInserter.insert(text) {
        case .pasted: print("Pasted into the frontmost app.")
        case .copiedOnly(let reason): print("Copied to the clipboard only: \(reason)")
        }
    }
}
