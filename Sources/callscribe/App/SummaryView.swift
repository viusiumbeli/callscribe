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
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(tasks, id: \.index) { task in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Toggle("", isOn: Binding(
                                    get: { task.done },
                                    set: { _ in onToggle(task.index) }
                                ))
                                .toggleStyle(.checkbox)
                                .labelsHidden()

                                Text(.init(task.text))
                                    .strikethrough(task.done, color: .secondary)
                                    .foregroundStyle(task.done ? .secondary : .primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .contextMenu { Button("Copy") { copyToPasteboard(task.text) } }

                                Spacer(minLength: 0)

                                Button {
                                    onDeleteTask(task.index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .help("Delete this task")
                                .pointerCursor()
                            }
                        }
                    }
                    .textSelection(.enabled)   // select/copy across tasks
                }
            }
        }
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
