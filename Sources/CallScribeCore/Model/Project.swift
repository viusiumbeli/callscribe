import Foundation

/// A project groups calls under a user-chosen working directory. Recordings for
/// the project are stored there, and the summarizer (`claude`) runs with that
/// directory as its working directory — so folder access is intentional and
/// scoped to a place the user picked.
public struct Project: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    /// Filesystem path to the project's working directory.
    public var path: String

    public init(id: String, name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }

    public var rootURL: URL { URL(fileURLWithPath: path) }

    /// Filesystem-friendly folder name for a project title: lowercased, letters
    /// and digits kept (any script), every run of other characters collapsed to
    /// a single "_" — e.g. "Work calls" → "work_calls".
    public static func folderSlug(_ name: String) -> String {
        var result = ""
        var pendingSeparator = false
        for ch in name.lowercased() {
            if ch.isLetter || ch.isNumber {
                if pendingSeparator && !result.isEmpty { result.append("_") }
                pendingSeparator = false
                result.append(ch)
            } else {
                pendingSeparator = true
            }
        }
        return result.isEmpty ? "callscribe" : result
    }
}
