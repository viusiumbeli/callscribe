import CallScribeCore
import SwiftUI

/// Renders the summary Markdown as native blocks: each `## section` is a
/// GroupBox, agreements are a bullet list, and "My tasks" are checkable items
/// whose state is persisted via `onToggle`.
struct SummaryView: View {
    let markdown: String
    /// Called with a task's global index when its checkbox is toggled.
    var onToggle: (Int) -> Void

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
                        isExpanded: expansion(section.title)
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
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").foregroundStyle(.secondary)
                                Text(.init(item))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                case .tasks(let tasks):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(tasks, id: \.index) { task in
                            Toggle(isOn: Binding(
                                get: { task.done },
                                set: { _ in onToggle(task.index) }
                            )) {
                                Text(.init(task.text))
                                    .strikethrough(task.done, color: .secondary)
                                    .foregroundStyle(task.done ? .secondary : .primary)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }
        }
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
