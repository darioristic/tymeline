import XCTest
@testable import TymelineCore

final class WorkspaceTests: XCTestCase {
    func testDefaultsAreReasonable() {
        let ws = Workspace(name: "Work")
        XCTAssertEqual(ws.pollIntervalSeconds, 30)
        XCTAssertTrue(ws.enabled)
        XCTAssertNil(ws.linearUserId)
        XCTAssertNil(ws.clockifyWorkspaceId)
        XCTAssertNil(ws.clockifyUserId)
        XCTAssertFalse(ws.colorHex.isEmpty)
    }

    func testCodableRoundTripPreservesAllFields() throws {
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

        XCTAssertEqual(decoded, original)
    }

    func testTwoWorkspacesWithSameNameAreDistinctById() {
        let a = Workspace(name: "Work")
        let b = Workspace(name: "Work")
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(a, b)
    }
}
