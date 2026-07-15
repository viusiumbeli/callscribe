import SwiftUI

/// The primary window: a three-column layout — projects, the selected project's
/// calls (record button on top), and the selected call's detail.
struct MainWindowView: View {
    @Bindable var state: AppState

    @State private var selectedCallID: String?
    @State private var showNewProject = false

    var body: some View {
        NavigationSplitView {
            ProjectsSidebar(state: state, onAddProject: { showNewProject = true })
        } content: {
            VStack(spacing: 0) {
                if case .failed(let message) = state.phase {
                    ErrorBanner(message: message) { state.clearError() }
                        .padding([.horizontal, .top], 10)
                }
                CallsColumn(state: state, selection: $selectedCallID)
            }
            .navigationTitle(state.selectedProject.name)
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
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet { name, parent in
                state.addProject(name: name, parentURL: parent)
            }
        }
    }
}
