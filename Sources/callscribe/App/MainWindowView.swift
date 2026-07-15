import AppKit
import CallScribeCore
import SwiftUI

/// The primary window: a two-column split (the selected project's calls and the
/// call detail). Project switching + New live in the window title-bar toolbar.
struct MainWindowView: View {
    @Bindable var state: AppState

    @State private var selectedCallID: String?
    @State private var showNewProject = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                if case .failed(let message) = state.phase {
                    ErrorBanner(message: message) { state.clearError() }
                        .padding([.horizontal, .top], 10)
                }
                CallsColumn(state: state, selection: $selectedCallID)
            }
        } detail: {
            if let call = state.calls.first(where: { $0.id == selectedCallID }) {
                CallDetailView(state: state, call: call) { selectedCallID = nil }
                    .id(call.id)
            } else {
                ContentUnavailableView("No call selected", systemImage: "waveform")
            }
        }
        .frame(minWidth: 900, minHeight: 520)
        .onChange(of: state.selectedProjectID) { selectedCallID = nil }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                ForEach(state.projects) { project in
                    projectButton(project)
                }
                Button {
                    showNewProject = true
                } label: {
                    Label("New", systemImage: "plus")
                }
                .help("Create a new project")
            }
        }
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet { name, parent in
                state.addProject(name: name, parentURL: parent)
            }
        }
    }

    private func projectButton(_ project: Project) -> some View {
        let isSelected = project.id == state.selectedProjectID
        return Button {
            state.selectedProjectID = project.id
        } label: {
            Text(project.name)
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
