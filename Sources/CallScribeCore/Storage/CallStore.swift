import Foundation

/// Storage is plain folders: one folder per call under the root, named by
/// start time. In-app history is just a listing of this directory.
public struct CallStore: Sendable {
    public let rootURL: URL

    public init(rootURL: URL? = nil) {
        self.rootURL = rootURL
            ?? FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/CallNotes")
    }

    public func createCallFolder(startedAt: Date) throws -> CallFolder {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let base = formatter.string(from: startedAt)

        var candidate = rootURL.appendingPathComponent(base)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = rootURL.appendingPathComponent("\(base)-\(suffix)")
            suffix += 1
        }
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        return CallFolder(url: candidate)
    }

    /// All call folders, newest first (by folder name, which encodes the date).
    public func listCalls() throws -> [CallFolder] {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map(CallFolder.init(url:))
    }

    /// Delete a call's entire folder — audio, transcript, summary, meta.json and
    /// the hidden `.cache/` — recursively, leaving nothing behind.
    public func delete(_ folder: CallFolder) throws {
        try FileManager.default.removeItem(at: folder.url)
    }
}
