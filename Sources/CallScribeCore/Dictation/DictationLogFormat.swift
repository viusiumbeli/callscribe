import Foundation

/// The `dictations.md` format, both directions — the inverse pair to what
/// `DictationLog` writes, in the same spirit as `TranscriptMarkdownRenderer` and
/// `TranscriptParse`.
///
/// Render *and* parse live together here on purpose. Deleting an entry means
/// rewriting the file, and that file is the only record of what you dictated, so
/// a format defined in two places is a format that will eventually disagree with
/// itself. The round-trip is unit-tested for exactly that reason.
///
/// The shape, per entry:
///
/// ```
/// ## 2026-08-10 13:05:32 · en
///
/// Ship it.
/// ```
///
/// The ` · en` language suffix is optional — entries written before it was
/// threaded through don't have one — and the body runs to the next `## ` at line
/// start, since dictated text can contain newlines.
public enum DictationLogFormat {
    public struct Entry: Equatable, Sendable, Identifiable {
        /// nil when a hand-edited stamp won't parse. The entry is still returned:
        /// showing it undated beats dropping something the user said.
        public let date: Date?
        public let language: String?
        public let text: String
        /// Ordinal in the file, counting from 0. The address `remove` takes —
        /// display order is newest-first and filtered, so a row's position on
        /// screen says nothing about its position on disk.
        public let index: Int

        public var id: Int { index }

        public init(date: Date?, language: String?, text: String, index: Int) {
            self.date = date
            self.language = language
            self.text = text
            self.index = index
        }
    }

    /// Written once, when the file is created.
    public static let preamble = "# Dictations\n\n"

    /// One entry, ready to append.
    public static func render(_ text: String, at date: Date, language: String?) -> String {
        let suffix = language.map { " · \($0)" } ?? ""
        return "## \(timestamp.string(from: date))\(suffix)\n\n\(text)\n\n"
    }

    /// Every entry in the file, in file order (oldest first).
    public static func parse(_ markdown: String) -> [Entry] {
        var entries: [Entry] = []
        var heading: (date: Date?, language: String?)?
        var body: [String] = []

        func flush() {
            guard let heading else { return }
            let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            entries.append(Entry(
                date: heading.date,
                language: heading.language,
                text: text,
                index: entries.count
            ))
            body = []
        }

        for line in markdown.components(separatedBy: "\n") {
            guard let parsed = parseHeading(line) else {
                // Everything that isn't a heading belongs to the entry above it.
                // Text before the first heading (the `# Dictations` preamble) has
                // no entry to belong to and is dropped.
                if heading != nil { body.append(line) }
                continue
            }
            flush()
            heading = parsed
        }
        flush()
        return entries
    }

    /// The file with entry `index` gone. Out of range, or unparseable input,
    /// returns the input untouched — never a partial rewrite.
    ///
    /// Line-based like `SummaryMarkdown.removeTask`, so every line that isn't
    /// part of the removed entry survives byte-identically: the preamble, and any
    /// hand-editing the user has done to the rest of the file.
    public static func remove(_ markdown: String, index: Int) -> String {
        var lines = markdown.components(separatedBy: "\n")
        var seen = -1
        var start: Int?

        for i in lines.indices where parseHeading(lines[i]) != nil {
            seen += 1
            if seen == index {
                start = i
            } else if let start {
                // The next heading bounds the entry we're dropping.
                lines.removeSubrange(start..<i)
                return joined(lines)
            }
        }
        guard let start else { return markdown }
        lines.removeSubrange(start..<lines.count)   // it was the last entry
        return joined(lines)
    }

    /// Rejoin, ending in exactly one blank line.
    ///
    /// Removing the *last* entry otherwise leaves the file ending in a single
    /// newline, and the next `append` would then glue its heading onto the
    /// previous entry's body. Deleting everything leaves precisely the preamble.
    private static func joined(_ lines: [String]) -> String {
        var text = lines.joined(separator: "\n")
        while text.hasSuffix("\n") { text.removeLast() }
        return text.isEmpty ? "" : text + "\n\n"
    }

    // MARK: - Heading

    /// `## <stamp>` with an optional ` · <language>`, or nil for any other line.
    /// Returns a nil `date` for a heading whose stamp doesn't parse, which is
    /// still a heading — the entry boundary is the `## `, not the timestamp.
    private static func parseHeading(_ line: String) -> (date: Date?, language: String?)? {
        guard line.hasPrefix("## ") else { return nil }
        let rest = line.dropFirst(3).trimmingCharacters(in: .whitespaces)

        let stamp: String
        let language: String?
        if let separator = rest.range(of: " · ") {
            stamp = String(rest[..<separator.lowerBound])
            let tail = rest[separator.upperBound...].trimmingCharacters(in: .whitespaces)
            language = tail.isEmpty ? nil : tail
        } else {
            stamp = rest
            language = nil
        }
        return (timestamp.date(from: stamp), language)
    }

    /// Local time, no zone marker — the file is read by a human, in their own
    /// timezone. Parsing must use this same formatter; ISO8601 would reject it.
    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
