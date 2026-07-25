import Foundation

/// Parses the summarizer's Markdown into displayable sections and lets the UI
/// toggle "My tasks" checklist items. Pure — the view renders the result and
/// persists toggles back to summary.md.
public enum SummaryMarkdown {
    public struct Task: Equatable, Sendable {
        public var text: String
        public var done: Bool
        /// Position among all task items in the document (0-based); used to
        /// address the item when toggling.
        public var index: Int
    }

    public enum Block: Equatable, Sendable {
        case paragraph(String)
        case bullets([String])
        case tasks([Task])
    }

    public struct Section: Equatable, Sendable {
        /// Heading text ("Summary", "My tasks", …); empty for content that
        /// appears before the first heading.
        public var title: String
        public var blocks: [Block]
        /// Heading depth (number of leading `#`); 0 for pre-heading content.
        public var level: Int = 0
        /// Deeper headings nested under this one (`###` topics under `## Topics`).
        public var subsections: [Section] = []
    }

    public static func parse(_ markdown: String) -> [Section] {
        nest(parseFlat(markdown))
    }

    /// Sections in document order, each carrying its heading depth — the input
    /// to `nest`.
    static func parseFlat(_ markdown: String) -> [Section] {
        var sections: [Section] = []
        var current = Section(title: "", blocks: [])
        var taskCounter = 0

        var paragraph: [String] = []
        var bullets: [String] = []
        var tasks: [Task] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                current.blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }
        func flushBullets() {
            if !bullets.isEmpty { current.blocks.append(.bullets(bullets)); bullets = [] }
        }
        func flushTasks() {
            if !tasks.isEmpty { current.blocks.append(.tasks(tasks)); tasks = [] }
        }
        func flushAll() { flushParagraph(); flushBullets(); flushTasks() }
        func flushSection() {
            flushAll()
            if !current.title.isEmpty || !current.blocks.isEmpty { sections.append(current) }
            current = Section(title: "", blocks: [])
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("#") {
                flushSection()
                current.level = line.prefix(while: { $0 == "#" }).count
                current.title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            } else if let task = parseTask(line, index: taskCounter) {
                flushParagraph(); flushBullets()
                tasks.append(task); taskCounter += 1
            } else if let bullet = parseBullet(line) {
                flushParagraph(); flushTasks()
                bullets.append(bullet)
            } else if line.isEmpty {
                flushAll()
            } else {
                flushBullets(); flushTasks()
                paragraph.append(line)
            }
        }
        flushSection()
        return sections
    }

    /// Fold a flat, depth-tagged section list into a tree: each section becomes a
    /// subsection of the nearest preceding shallower one (so `### topics` nest
    /// under `## Topics`). A deeper heading with no shallower parent degrades to a
    /// root section; pre-heading content (level 0, untitled) is always a root and
    /// never adopts what follows it.
    static func nest(_ flat: [Section]) -> [Section] {
        var roots: [Section] = []
        var open: [Section] = []   // ancestors being filled, strictly increasing level

        /// Close every open section at or below `level`, attaching each to its
        /// parent (or to the roots once the stack empties).
        func close(downTo level: Int) {
            while let child = open.last, child.level >= level {
                open.removeLast()
                if var parent = open.popLast() {
                    parent.subsections.append(child)
                    open.append(parent)
                } else {
                    roots.append(child)
                }
            }
        }

        for section in flat {
            guard section.level > 0 else { roots.append(section); continue }
            close(downTo: section.level)
            open.append(section)
        }
        close(downTo: 1)
        return roots
    }

    /// Split a leading `[HH:MM:SS]` / `[MM:SS]` timecode off a heading, returning
    /// its position in seconds and the remaining text. Tolerates a missing
    /// bracket and a `—`/`-`/`:` separator; yields `(nil, title)` when there's no
    /// timecode, so a topic without one still renders.
    public static func splitTimecode(_ title: String) -> (start: TimeInterval?, text: String) {
        let pattern = /^\[?\s*(\d{1,2}):(\d{2})(?::(\d{2}))?\s*\]?\s*[-–—:]?\s*(.*)$/
        guard let m = title.trimmingCharacters(in: .whitespaces).wholeMatch(of: pattern) else {
            return (nil, title)
        }
        let first = Int(m.1) ?? 0, second = Int(m.2) ?? 0
        // Three groups ⇒ H:MM:SS; two ⇒ MM:SS.
        let seconds = m.3.flatMap { Int($0) }.map { TimeInterval(first * 3600 + second * 60 + $0) }
            ?? TimeInterval(first * 60 + second)
        let text = String(m.4).trimmingCharacters(in: .whitespaces)
        return (seconds, text.isEmpty ? title : text)
    }

    /// Flip the `index`-th checklist item in `markdown` and return the result.
    public static func toggleTask(_ markdown: String, index: Int) -> String {
        var count = 0
        var lines = markdown.components(separatedBy: "\n")
        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            guard trimmed.wholeMatch(of: /[-*]\s+\[[ xX]\]\s+.*/) != nil else { continue }
            if count == index {
                if let r = lines[i].range(of: "[ ]") {
                    lines[i].replaceSubrange(r, with: "[x]")
                } else if let r = lines[i].range(of: "[x]") ?? lines[i].range(of: "[X]") {
                    lines[i].replaceSubrange(r, with: "[ ]")
                }
                break
            }
            count += 1
        }
        return lines.joined(separator: "\n")
    }

    /// Remove the `index`-th checklist item line entirely and return the result.
    public static func removeTask(_ markdown: String, index: Int) -> String {
        var count = 0
        var lines = markdown.components(separatedBy: "\n")
        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            guard trimmed.wholeMatch(of: /[-*]\s+\[[ xX]\]\s+.*/) != nil else { continue }
            if count == index {
                lines.remove(at: i)
                break
            }
            count += 1
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Line parsing

    static func parseTask(_ line: String, index: Int) -> Task? {
        guard let m = line.wholeMatch(of: /[-*]\s+\[([ xX])\]\s+(.*)/) else { return nil }
        return Task(text: String(m.2), done: m.1.lowercased() == "x", index: index)
    }

    static func parseBullet(_ line: String) -> String? {
        guard let m = line.wholeMatch(of: /[-*]\s+(.*)/) else { return nil }
        return String(m.1)
    }
}
