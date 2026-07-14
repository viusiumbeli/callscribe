import ArgumentParser
import CallScribeEngine
import Foundation

struct ProbeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "probe",
        abstract: "Record a few seconds from mic + system audio to verify capture and permissions."
    )

    @Option(name: .shortAndLong, help: "How long to record.")
    var seconds: UInt = 10

    @Option(name: .shortAndLong, help: "Output directory (default: a temporary folder).")
    var output: String?

    func run() async throws {
        print("Recording \(seconds) s from microphone + system audio…")
        print("(play some audio in another app so system.wav has content)")
        let result = try await ProbeRunner.run(
            seconds: seconds,
            outputDir: output.map { URL(fileURLWithPath: $0) }
        )
        print("mic:    \(result.micURL.path) (\(String(format: "%.1f", result.micSeconds)) s)")
        print("system: \(result.systemURL.path) (\(String(format: "%.1f", result.systemSeconds)) s)")
    }
}
