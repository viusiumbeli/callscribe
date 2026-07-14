import Foundation

/// Standard on-disk locations. ML models live under Application Support so they
/// never pollute the user's call folders in ~/Documents.
public enum AppPaths {
    public static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CallScribe/Models", isDirectory: true)
    }

    public static func ensureModelsDirectory() throws -> URL {
        let dir = modelsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
