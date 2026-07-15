import AppKit
import SwiftUI

/// Left column: the list of projects. Selecting one switches which project's
/// recordings are shown; "+" creates a new one.
struct ProjectsSidebar: View {
    @Bindable var state: AppState
    var onAddProject: () -> Void

    var body: some View {
        List(selection: projectSelection) {
            Section("Projects") {
                ForEach(state.projects) { project in
                    Label(project.name, systemImage: "folder")
                        .tag(project.id)
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
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                Button(action: onAddProject) {
                    Label("New Project", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(12)
                Divider()
            }
            .background(.bar)
        }
    }

    private var projectSelection: Binding<String?> {
        Binding(
            get: { state.selectedProjectID },
            set: { if let id = $0 { state.selectedProjectID = id } }
        )
    }
}
