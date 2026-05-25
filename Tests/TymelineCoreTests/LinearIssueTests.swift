import Testing
import Foundation
@testable import TymelineCore

@Suite("LinearIssue")
struct LinearIssueTests {
    private func make(
        stateType: LinearIssueStateType,
        assigneeId: String? = "user-me"
    ) -> LinearIssue {
        LinearIssue(
            id: "iss-1",
            identifier: "ENG-1",
            title: "Test",
            stateType: stateType,
            stateName: "Test State",
            assigneeId: assigneeId,
            projectId: "proj-1",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test func isActiveForMeTrueWhenStartedAndAssigned() {
        let issue = make(stateType: .started, assigneeId: "user-me")
        #expect(issue.isActiveForMe)
    }

    @Test func isActiveForMeFalseWhenUnstartedEvenIfAssigned() {
        let issue = make(stateType: .unstarted, assigneeId: "user-me")
        #expect(!issue.isActiveForMe)
    }

    @Test func isActiveForMeFalseWhenCompletedEvenIfAssigned() {
        let issue = make(stateType: .completed, assigneeId: "user-me")
        #expect(!issue.isActiveForMe)
    }

    @Test func isActiveForMeFalseWhenStartedButUnassigned() {
        let issue = make(stateType: .started, assigneeId: nil)
        #expect(!issue.isActiveForMe)
    }

    @Test func codableRoundTrip() throws {
        let original = make(stateType: .started)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LinearIssue.self, from: data)

        #expect(decoded == original)
    }

    @Test func stateTypeDecodesFromLinearLowercaseString() throws {
        let json = "\"started\"".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LinearIssueStateType.self, from: json)
        #expect(decoded == .started)
    }

    @Test func stateTypeDecodesAllLinearStateTypes() throws {
        let cases: [(String, LinearIssueStateType)] = [
            ("backlog", .backlog),
            ("unstarted", .unstarted),
            ("started", .started),
            ("completed", .completed),
            ("canceled", .canceled),
            ("triage", .triage),
        ]
        for (raw, expected) in cases {
            let json = "\"\(raw)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(LinearIssueStateType.self, from: json)
            #expect(decoded == expected, "\(raw) should decode to .\(expected)")
        }
    }
}
