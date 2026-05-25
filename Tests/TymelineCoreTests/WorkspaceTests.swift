import Testing
import Foundation
@testable import TymelineCore

@Suite("Workspace")
struct WorkspaceTests {
    @Test func defaultsAreReasonable() {
        let ws = Workspace(name: "Work")
        #expect(ws.pollIntervalSeconds == 30)
        #expect(ws.enabled == true)
        #expect(ws.linearUserId == nil)
        #expect(ws.clockifyWorkspaceId == nil)
        #expect(ws.clockifyUserId == nil)
        #expect(!ws.colorHex.isEmpty)
    }

    @Test func codableRoundTripPreservesAllFields() throws {
        let original = Workspace(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Personal",
            colorHex: "#FF8800",
            pollIntervalSeconds: 60,
            enabled: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500),
            linearUserId: "lin-user-1",
            clockifyWorkspaceId: "ck-ws-1",
            clockifyUserId: "ck-user-1"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Workspace.self, from: data)

        #expect(decoded == original)
    }

    @Test func twoWorkspacesWithSameNameAreDistinctById() {
        let a = Workspace(name: "Work")
        let b = Workspace(name: "Work")
        #expect(a.id != b.id)
        #expect(a != b)
    }
}
