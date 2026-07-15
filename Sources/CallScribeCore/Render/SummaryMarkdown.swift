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
    }

    public static func parse(_ markdown: String) -> [Section] {
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
