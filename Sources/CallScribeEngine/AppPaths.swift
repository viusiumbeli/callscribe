import Foundation

/// Standard on-disk locations. ML models live under Application Support so they
/// never pollute the user's call folders in ~/Documents.
public enum AppPaths {
    public static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CallScribe/Models", isDirectory: true)
    }

    /// Dictated text, appended one entry at a time. Beside `projects.json` in
    /// Application Support rather than in `~/Library/Logs`: unlike the
    /// diagnostics log this holds *content*, and `~/Library/Logs` is swept up by
    /// `sysdiagnose`.
    public static var dictationLogURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CallScribe/dictations.md")
    }

    /// Diagnostics log location — the macOS convention, so Console.app lists it.
    public static var logsDirectory: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Logs/CallScribe", isDirectory: true)
    }

    public static func ensureModelsDirectory() throws -> URL {
        let dir = modelsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
