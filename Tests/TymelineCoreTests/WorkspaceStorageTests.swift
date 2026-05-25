import Testing
import Foundation
@testable import TymelineCore

@Suite("WorkspaceStorage")
struct WorkspaceStorageTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "tymeline-test-\(UUID().uuidString).json"
        )
    }

    @Test func loadReturnsEmptyArrayWhenFileMissing() async throws {
        let url = tempURL()
        let storage = WorkspaceStorage(url: url)
        let result = try await storage.load()
        #expect(result.isEmpty)
    }

    @Test func saveAndLoadRoundTripPreservesWorkspaces() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let storage = WorkspaceStorage(url: url)
        let workspaces = [
            Workspace(
                name: "Work",
                colorHex: "#FF0000",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                linearUserId: "lin-1"
            ),
            Workspace(
                name: "Personal",
                colorHex: "#00FF00",
                createdAt: Date(timeIntervalSince1970: 1_700_000_500),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_500)
            ),
        ]
        try await storage.save(workspaces)

        let loaded = try await storage.load()
        #expect(loaded == workspaces)
    }

    @Test func saveOverwritesExistingFile() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let storage = WorkspaceStorage(url: url)
        try await storage.save([Workspace(name: "A")])
        try await storage.save([Workspace(name: "B"), Workspace(name: "C")])

        let loaded = try await storage.load()
        #expect(loaded.count == 2)
        #expect(loaded.map(\.name) == ["B", "C"])
    }

    @Test func loadHandlesEmptyFile() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try Data().write(to: url)
        let storage = WorkspaceStorage(url: url)
        let result = try await storage.load()
        #expect(result.isEmpty)
    }

    @Test func savedJSONIsHumanReadable() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let storage = WorkspaceStorage(url: url)
        try await storage.save([Workspace(name: "Work")])

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("\n"))     // pretty-printed
        #expect(raw.contains("\"name\""))
        #expect(raw.contains("Work"))
    }
}
