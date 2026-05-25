import Testing
import Foundation
@testable import TymelineCore

@Suite("TransitionDetector")
struct TransitionDetectorTests {
    let detector = TransitionDetector()
    let me = "user-me"
    let other = "user-other"

    private func issue(
        id: String,
        identifier: String? = nil,
        state: LinearIssueStateType,
        assignee: String?,
        title: String = "Test",
        updated: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> LinearIssue {
        LinearIssue(
            id: id,
            identifier: identifier ?? "ENG-\(id)",
            title: title,
            stateType: state,
            stateName: state.rawValue.capitalized,
            assigneeId: assignee,
            projectId: "proj-1",
            updatedAt: updated
        )
    }

    @Test func noChangeYieldsNoTransitions() {
        let issues = [
            issue(id: "a", state: .started, assignee: me),
            issue(id: "b", state: .unstarted, assignee: me),
        ]
        let transitions = detector.detect(previous: issues, current: issues, userId: me)
        #expect(transitions.isEmpty)
    }

    @Test func firstPollWithActiveIssueYieldsStarted() {
        let active = issue(id: "a", state: .started, assignee: me)
        let transitions = detector.detect(previous: [], current: [active], userId: me)
        #expect(transitions == [.started(active)])
    }

    @Test func issueMovedFromUnstartedToStartedYieldsStarted() {
        let before = issue(id: "a", state: .unstarted, assignee: me)
        let after = issue(id: "a", state: .started, assignee: me)
        let transitions = detector.detect(previous: [before], current: [after], userId: me)
        #expect(transitions == [.started(after)])
    }

    @Test func issueMovedFromStartedToCompletedYieldsStoppedWithStateChanged() {
        let before = issue(id: "a", state: .started, assignee: me)
        let after = issue(id: "a", state: .completed, assignee: me)
        let transitions = detector.detect(previous: [before], current: [after], userId: me)
        #expect(transitions == [.stopped(before, reason: .stateChanged(.completed))])
    }

    @Test func issueReassignedAwayFromMeYieldsStoppedWithUnassigned() {
        let before = issue(id: "a", state: .started, assignee: me)
        let after = issue(id: "a", state: .started, assignee: other)
        let transitions = detector.detect(previous: [before], current: [after], userId: me)
        #expect(transitions == [.stopped(before, reason: .unassigned)])
    }

    @Test func issueDisappearedFromCurrentYieldsStoppedWithDisappeared() {
        let before = issue(id: "a", state: .started, assignee: me)
        let transitions = detector.detect(previous: [before], current: [], userId: me)
        #expect(transitions == [.stopped(before, reason: .disappeared)])
    }

    @Test func newActiveIssueAppearsYieldsStarted() {
        let existing = issue(id: "a", state: .started, assignee: me)
        let newOne = issue(id: "b", state: .started, assignee: me)
        let transitions = detector.detect(
            previous: [existing],
            current: [existing, newOne],
            userId: me
        )
        #expect(transitions == [.started(newOne)])
    }

    @Test func switchingActiveIssueYieldsBothStoppedAndStarted() {
        let dropped = issue(id: "a", state: .started, assignee: me)
        let droppedNow = issue(id: "a", state: .unstarted, assignee: me)
        let newActive = issue(id: "b", state: .started, assignee: me)
        let transitions = detector.detect(
            previous: [dropped],
            current: [droppedNow, newActive],
            userId: me
        )
        #expect(transitions.count == 2)
        #expect(transitions.contains(.stopped(dropped, reason: .stateChanged(.unstarted))))
        #expect(transitions.contains(.started(newActive)))
    }

    @Test func titleChangeOnActiveIssueYieldsUpdated() {
        let before = issue(id: "a", state: .started, assignee: me, title: "Old title")
        let after = issue(id: "a", state: .started, assignee: me, title: "New title")
        let transitions = detector.detect(previous: [before], current: [after], userId: me)
        #expect(transitions == [.updated(after)])
    }

    @Test func ignoresIssuesActiveForOtherUsers() {
        let mine = issue(id: "a", state: .started, assignee: me)
        let theirs = issue(id: "b", state: .started, assignee: other)
        // Both polls have the same set; only `mine` is active for me, no change.
        let transitions = detector.detect(
            previous: [mine, theirs],
            current: [mine, theirs],
            userId: me
        )
        #expect(transitions.isEmpty)
    }

    @Test func assignedToMeOnAlreadyStartedIssueYieldsStarted() {
        let before = issue(id: "a", state: .started, assignee: other)
        let after = issue(id: "a", state: .started, assignee: me)
        let transitions = detector.detect(previous: [before], current: [after], userId: me)
        #expect(transitions == [.started(after)])
    }
}
