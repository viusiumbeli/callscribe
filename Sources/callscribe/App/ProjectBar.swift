import AppKit
import CallScribeCore
import SwiftUI

/// Full-width strip at the top of the window: project chips for quick switching,
/// with a "+" at the end to create a new project.
struct ProjectBar: View {
    @Bindable var state: AppState
    var onAddProject: () -> Void
    var onToggleSidebar: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onToggleSidebar) {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.borderless)
                .help("Show or hide the calls list")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(state.projects) { project in
                            chip(project)
                        }
                    }
                }

                Button(action: onAddProject) {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .help("Create a new project")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
        }
        .background(.bar)
    }

    private func chip(_ project: Project) -> some View {
        let isSelected = project.id == state.selectedProjectID
        return Button {
            state.selectedProjectID = project.id
        } label: {
            Label(project.name, systemImage: "folder")
                .lineLimit(1)
        }
        .buttonStyle(.borderedProminent)
        .tint(isSelected ? Color.accentColor : Color(nsColor: .controlColor))
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([project.rootURL])
            }
            if state.projects.count > 1 {
                Button("Remove from CallScribe", role: .destructive) {
                    state.removeProject(project.id)
                }
            }
        }
    }
}
