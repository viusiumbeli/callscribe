import Foundation
import Testing
@testable import CallScribeCore

private func tempFile() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("projects-\(UUID().uuidString).json")
}

@Suite struct ProjectStoreTests {
    @Test func seedsDefaultProjectOnFirstLoad() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProjectStore(fileURL: url)

        let state = store.load(defaultProject: Project(id: "d", name: "Default", path: "/tmp/x"))
        #expect(state.projects.count == 1)
        #expect(state.selectedID == "d")
        #expect(FileManager.default.fileExists(atPath: url.path), "default is persisted")
    }

    @Test func roundTripsProjectsAndSelection() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProjectStore(fileURL: url)

        let state = ProjectStore.State(
            projects: [
                Project(id: "a", name: "Work", path: "/tmp/work"),
                Project(id: "b", name: "Personal", path: "/tmp/personal"),
            ],
            selectedID: "b"
        )
        try store.save(state)

        let loaded = ProjectStore(fileURL: url).load()
        #expect(loaded.projects.map(\.id) == ["a", "b"])
        #expect(loaded.selectedID == "b")
    }

    @Test func repairsDanglingSelection() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProjectStore(fileURL: url)
        try store.save(.init(projects: [Project(id: "a", name: "A", path: "/tmp/a")], selectedID: "gone"))

        let loaded = store.load()
        #expect(loaded.selectedID == "a")
    }
}
