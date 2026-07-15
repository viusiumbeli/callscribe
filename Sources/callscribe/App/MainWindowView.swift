import SwiftUI

/// The primary window: a project bar across the top, then a two-column split —
/// the selected project's calls (record button on top) and the call detail.
struct MainWindowView: View {
    @Bindable var state: AppState

    @State private var selectedCallID: String?
    @State private var showNewProject = false

    var body: some View {
        VStack(spacing: 0) {
            ProjectBar(state: state, onAddProject: { showNewProject = true })

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
