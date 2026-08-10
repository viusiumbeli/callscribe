import AppKit
import ArgumentParser

@main
struct CallScribeMain {
    /// Deliberately **not** `async`.
    ///
    /// An `async main` runs its body inside a Swift concurrency task, so
    /// `NSApplicationMain` would start AppKit's run loop nested in a task
    /// continuation rather than owning the process's main thread. AppKit tolerates
    /// that just far enough to be misleading: the app draws, and activates once at
    /// launch — but it can never *re*-activate after losing focus. `NSApp.isActive`
    /// stays false, no window becomes key, and every click goes to whatever is
    /// behind it, even while LaunchServices reports the app as frontmost. From the
    /// outside that looks exactly like a frozen UI, with a perfectly idle main
    /// thread and a healthy window.
    ///
    /// So the GUI path gets a plain synchronous `main`, and the CLI's async entry
    /// point is driven from the main queue instead (see below).
    @MainActor
    static func main() {
        if isAppLaunch(Array(CommandLine.arguments.dropFirst())) {
            CallScribeApp.main()
        } else {
            // `dispatchMain()` rather than a semaphore: it parks the main thread as
            // the main-queue server, so `@MainActor` work inside the CLI (e.g.
            // `TextInserter`) still runs. A semaphore would deadlock on the first
            // main-actor hop.
            //
            // The explicit `exit(0)` is load-bearing: `dispatchMain()` never
            // returns, and ArgumentParser's `main()` does *not* reliably exit on
            // the success path — without this, every successful CLI command hangs
            // forever after printing its output.
            Task {
                await CallScribeCLI.main()
                exit(0)
            }
            dispatchMain()
        }
    }

    /// LaunchServices launches carry no subcommand (and may pass `-flags`);
    /// anything that isn't a known subcommand is treated as an app launch.
    private static func isAppLaunch(_ args: [String]) -> Bool {
        guard let first = args.first(where: { !$0.hasPrefix("-") }) else {
            return args.isEmpty || !args.contains("--help") && !args.contains("-h")
        }
        return !CallScribeCLI.subcommandNames.contains(first)
    }
}

struct CallScribeCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "callscribe",
        abstract: "Local call transcription for macOS.",
        subcommands: [
            RecordCommand.self,
            DictateCommand.self,
            SetupCommand.self,
            EchoCancelCommand.self,
            TranscribeCommand.self,
            DiarizeCommand.self,
            EnrollCommand.self,
            MergeCommand.self,
            SummarizeCommand.self,
            PipelineCommand.self,
            ProbeCommand.self,
            VersionCommand.self,
        ]
    )

    static var subcommandNames: [String] {
        configuration.subcommands.compactMap { $0.configuration.commandName }
    }
}
