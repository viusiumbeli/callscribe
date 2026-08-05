import Foundation

/// Append-only diagnostic log: one line per event, in `~/Library/Logs/CallScribe/`.
///
/// Errors used to exist only as a banner the user had to copy by hand, and two
/// pipeline stages swallow their failures entirely — this is the record that
/// survives a quit and can be grepped after the fact.
///
/// Deliberately synchronous: callers span engine actors, the `@MainActor` UI and
/// the CLI, and an `await` at every site would be noise for a sub-millisecond
/// append. An `NSLock` around the handle is enough.
///
/// **Never log call content.** No transcript, summary or prompt text — this app
/// records work calls, and `~/Library/Logs` is collected by `sysdiagnose`. Log
/// metadata only: folder names, stages, durations, exit codes, error text.
public final class Log: @unchecked Sendable {
    public static let shared = Log(directory: AppPaths.logsDirectory)

    public let fileURL: URL
    private let rotatedURL: URL
    private let maxBytes: Int
    private let lock = NSLock()
    private var handle: FileHandle?
    private let formatter: DateFormatter

    public init(directory: URL, maxBytes: Int = 2_000_000) {
        self.fileURL = directory.appendingPathComponent("callscribe.log")
        self.rotatedURL = directory.appendingPathComponent("callscribe.log.1")
        self.maxBytes = maxBytes
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        self.formatter = formatter
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func info(_ message: String) { write("INFO ", message) }
    public func warn(_ message: String) { write("WARN ", message) }
    public func error(_ message: String) { write("ERROR", message) }

    /// Trim a captured child-process stream to something a log line can hold —
    /// the one field that could carry more than metadata.
    public static func truncated(_ text: String, max: Int = 2048) -> String {
        text.count <= max ? text : String(text.prefix(max)) + "… (truncated)"
    }

    private func write(_ level: String, _ message: String) {
        // Fixed-width level so `grep ERROR` is reliable; a multi-line message is
        // indented so one event stays one grep hit plus its continuation.
        let indented = message.replacingOccurrences(of: "\n", with: "\n                          ")
        let line = "\(formatter.string(from: Date()))  \(level)  \(indented)\n"

        lock.lock()
        defer { lock.unlock() }
        guard let data = line.data(using: .utf8) else { return }
        rotateIfNeededLocked(adding: data.count)
        guard let handle = openLocked() else { return }
        try? handle.write(contentsOf: data)
    }

    private func openLocked() -> FileHandle? {
        if let handle { return handle }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let opened = try? FileHandle(forWritingTo: fileURL) else { return nil }
        _ = try? opened.seekToEnd()
        handle = opened
        return opened
    }

    /// Close → rename → reopen, in that order. A retained handle follows the
    /// inode, so renaming while holding it would send every later line into the
    /// rotated-away file. Size comes from the handle's own offset rather than a
    /// stat, so the check can't race the append.
    private func rotateIfNeededLocked(adding bytes: Int) {
        guard let handle else {
            // No handle yet: an existing file from a previous run may already be
            // over the cap, so consult the file system just this once.
            let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            let size = (attributes?[.size] as? Int) ?? 0
            if size + bytes > maxBytes { rotateLocked() }
            return
        }
        let size = Int((try? handle.offset()) ?? 0)
        guard size + bytes > maxBytes else { return }
        try? handle.close()
        self.handle = nil
        rotateLocked()
    }

    private func rotateLocked() {
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: fileURL, to: rotatedURL)
    }
}
