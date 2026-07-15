import AppKit
import ArgumentParser

@main
struct CallScribeMain {
    @MainActor
    static func main() async {
        if isAppLaunch(Array(CommandLine.arguments.dropFirst())) {
            CallScribeApp.main()
        } else {
            await CallScribeCLI.main()
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
            SetupCommand.self,
            EchoCancelCommand.self,
            TranscribeCommand.self,
            DiarizeCommand.self,
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
