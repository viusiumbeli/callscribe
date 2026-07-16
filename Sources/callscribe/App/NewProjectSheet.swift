import AppKit
import CallScribeCore
import SwiftUI

/// Create a project: name it, pick a parent folder. A dedicated subfolder for
/// this project's recordings is created inside that folder.
struct NewProjectSheet: View {
    var onCreate: (_ name: String, _ parent: URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var parent: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Project").font(.title3.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.callout).foregroundStyle(.secondary)
                TextField("e.g. Work calls", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Location").font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Choose Folder…") { pickFolder() }
                        .pointerCursor()
                    Text(parent?.path ?? "No folder chosen")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if let destination {
                Text("Recordings will be stored in:\n\(destination.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .pointerCursor()
                Button("Create") {
                    if let parent { onCreate(trimmedName, parent) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty || parent == nil)
                .pointerCursor()
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Preview of the dedicated folder that will be created.
    private var destination: URL? {
        guard let parent, !trimmedName.isEmpty else { return nil }
        return parent.appendingPathComponent(Project.folderSlug(trimmedName), isDirectory: true)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose where this project's folder will be created"
        if panel.runModal() == .OK { parent = panel.url }
    }
}
