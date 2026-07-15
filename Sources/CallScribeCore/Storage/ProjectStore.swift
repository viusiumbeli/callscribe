import Foundation

/// Persists the list of projects and which one is selected, in a small JSON
/// file under Application Support. Seeds a "Default" project pointing at
/// ~/Documents/CallNotes so existing recordings keep working.
public final class ProjectStore {
    public struct State: Codable, Sendable {
        public var projects: [Project]
        public var selectedID: String

        public init(projects: [Project], selectedID: String) {
            self.projects = projects
            self.selectedID = selectedID
        }
    }

    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = base.appendingPathComponent("CallScribe/projects.json")
        }
    }

    /// Load persisted state, seeding + saving a default project on first run.
    public func load(defaultProject: @autoclosure () -> Project = ProjectStore.makeDefault()) -> State {
        if let data = try? Data(contentsOf: fileURL),
           var state = try? JSONDecoder().decode(State.self, from: data),
           !state.projects.isEmpty {
            if !state.projects.contains(where: { $0.id == state.selectedID }) {
                state.selectedID = state.projects[0].id
            }
            return state
        }
        let project = defaultProject()
        let state = State(projects: [project], selectedID: project.id)
        try? save(state)
        return state
    }

    public func save(_ state: State) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: .atomic)
    }

    public static func makeDefault() -> Project {
        let path = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/CallNotes").path
        return Project(id: "default", name: "Default", path: path)
    }
}
