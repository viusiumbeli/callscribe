import AppKit
import CallScribeCore
import SwiftUI

/// Renders the summary Markdown as native cards: each `## section` is a
/// SectionCard, agreements are a bullet list, and "My tasks" are checkable,
/// deletable items whose state is persisted via the callbacks. Each section can
/// be copied as a whole.
struct SummaryView: View {
    let markdown: String
    /// Called with a task's global index when its checkbox is toggled.
    var onToggle: (Int) -> Void
    /// Called with a task's global index when it should be deleted.
    var onDeleteTask: (Int) -> Void

    /// Section titles the user has collapsed (empty ⇒ all expanded).
    @State private var collapsed: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(SummaryMarkdown.parse(markdown).enumerated()), id: \.offset) { _, section in
                if section.title.isEmpty {
                    blocks(section.blocks)
                } else {
                    SectionCard(
                        title: section.title,
                        systemImage: Self.icon(for: section.title),
                        isExpanded: expansion(section.title),
                        onCopy: { copyToPasteboard(Self.plainText(section)) }
                    ) {
                        blocks(section.blocks)
                    }
                }
            }
        }
    }

    private func expansion(_ title: String) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(title) },
            set: { open in
                if open { collapsed.remove(title) } else { collapsed.insert(title) }
            }
        )
    }

    private func blocks(_ blocks: [SummaryMarkdown.Block]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    Text(.init(text))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                case .bullets(let items):
                    // A single Text (not one per bullet) so a drag selects
                    // across lines — SwiftUI text selection can't span separate
                    // Text views.
                    Self.bulletText(items)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .contextMenu {
                            Button("Copy") {
                                copyToPasteboard(items.map { "- \($0)" }.joined(separator: "\n"))
                            }
                        }

                case .tasks(let tasks):
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(tasks, id: \.index) { task in
                            taskRow(task)
                        }
                    }
                }
            }
        }
    }

    /// A single "My tasks" item: a clear brand check-circle, the text, and a
    /// delete button, on its own subtly-filled row so tasks read as discrete,
    /// obviously-checkable items.
    private func taskRow(_ task: SummaryMarkdown.Task) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Button { onToggle(task.index) } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.done ? Color.brand : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(task.done ? "Mark as not done" : "Mark as done")
            .pointerCursor()

            Text(.init(task.text))
                .strikethrough(task.done, color: .secondary)
                .foregroundStyle(task.done ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .contextMenu { Button("Copy") { copyToPasteboard(task.text) } }

            Button { onDeleteTask(task.index) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Delete this task")
            .pointerCursor()
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.md)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Bullets as one concatenated Text (selectable across lines), keeping each
    /// item's inline markdown.
    static func bulletText(_ items: [String]) -> Text {
        var result = Text("")
        for (i, item) in items.enumerated() {
            if i > 0 { result = result + Text("\n") }
            result = result + Text("•  ").foregroundColor(.secondary) + Text(.init(item))
        }
        return result
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Serialize a section's blocks to portable plain text for copying.
    static func plainText(_ section: SummaryMarkdown.Section) -> String {
        var lines: [String] = []
        for block in section.blocks {
            switch block {
            case .paragraph(let text):
                lines.append(text)
            case .bullets(let items):
                lines.append(contentsOf: items.map { "- \($0)" })
            case .tasks(let tasks):
                lines.append(contentsOf: tasks.map { "- [\($0.done ? "x" : " ")] \($0.text)" })
            }
        }
        return lines.joined(separator: "\n")
    }

    static func icon(for title: String) -> String {
        switch title.lowercased() {
        case let t where t.contains("task"): "checklist"
        case let t where t.contains("agree"): "checkmark.seal"
        case let t where t.contains("summary"): "text.alignleft"
        default: "doc.text"
        }
    }
}
