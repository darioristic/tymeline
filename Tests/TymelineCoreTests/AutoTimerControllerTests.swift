import Testing
import Foundation
@testable import TymelineCore

@Suite("AutoTimerController")
struct AutoTimerControllerTests {
    let controller = AutoTimerController()

    private func issue(
        id: String,
        title: String = "Test"
    ) -> LinearIssue {
        LinearIssue(
            id: id,
            identifier: "ENG-\(id)",
            title: title,
            stateType: .started,
            stateName: "In Progress",
            assigneeId: "user-me",
            projectId: "proj-1",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test func emptyTransitionsAndNoRunningIssueYieldsNothing() {
        let decision = controller.decide(transitions: [], currentRunningIssueId: nil)
        #expect(decision.commands.isEmpty)
        #expect(decision.runningIssueId == nil)
    }

    @Test func emptyTransitionsWithRunningIssuePreservesIt() {
        let decision = controller.decide(transitions: [], currentRunningIssueId: "a")
        #expect(decision.commands.isEmpty)
        #expect(decision.runningIssueId == "a")
    }

    @Test func startedWithNoneRunningEmitsStart() {
        let a = issue(id: "a")
        let decision = controller.decide(
            transitions: [.started(a)],
            currentRunningIssueId: nil
        )
        #expect(decision.commands == [.start(issue: a)])
        #expect(decision.runningIssueId == "a")
    }

    @Test func startedForAlreadyRunningIssueIsNoOp() {
        let a = issue(id: "a")
        let decision = controller.decide(
            transitions: [.started(a)],
            currentRunningIssueId: "a"
        )
        #expect(decision.commands.isEmpty)
        #expect(decision.runningIssueId == "a")
    }

    @Test func startedForDifferentIssueStopsRunningAndStartsNew() {
        let b = issue(id: "b")
        let decision = controller.decide(
            transitions: [.started(b)],
            currentRunningIssueId: "a"
        )
        #expect(decision.commands == [.stop(issueId: "a"), .start(issue: b)])
        #expect(decision.runningIssueId == "b")
    }

    @Test func stoppedForRunningIssueEmitsStop() {
        let a = issue(id: "a")
        let decision = controller.decide(
            transitions: [.stopped(a, reason: .stateChanged(.completed))],
            currentRunningIssueId: "a"
        )
        #expect(decision.commands == [.stop(issueId: "a")])
        #expect(decision.runningIssueId == nil)
    }

    @Test func stoppedForNonRunningIssueIsNoOp() {
        let b = issue(id: "b")
        let decision = controller.decide(
            transitions: [.stopped(b, reason: .stateChanged(.completed))],
            currentRunningIssueId: "a"
        )
        #expect(decision.commands.isEmpty)
        #expect(decision.runningIssueId == "a")
    }

    @Test func switchingByExplicitStopAndStartEmitsBoth() {
        let a = issue(id: "a")
        let b = issue(id: "b")
        let decision = controller.decide(
            transitions: [
                .stopped(a, reason: .stateChanged(.unstarted)),
                .started(b),
            ],
            currentRunningIssueId: "a"
        )
        #expect(decision.commands == [.stop(issueId: "a"), .start(issue: b)])
        #expect(decision.runningIssueId == "b")
    }

    @Test func multipleStartsInOneBatchUseLastAsWinner() {
        let a = issue(id: "a")
        let b = issue(id: "b")
        let decision = controller.decide(
            transitions: [.started(a), .started(b)],
            currentRunningIssueId: nil
        )
        #expect(decision.commands == [.start(issue: b)])
        #expect(decision.runningIssueId == "b")
    }

    @Test func updatedForRunningIssueEmitsUpdateDescription() {
        let a = issue(id: "a", title: "New title")
        let decision = controller.decide(
            transitions: [.updated(a)],
            currentRunningIssueId: "a"
        )
        #expect(decision.commands == [.updateDescription(issue: a)])
        #expect(decision.runningIssueId == "a")
    }

    @Test func updatedForNonRunningIssueIsNoOp() {
        let b = issue(id: "b", title: "New title")
        let decision = controller.decide(
            transitions: [.updated(b)],
            currentRunningIssueId: "a"
        )
        #expect(decision.commands.isEmpty)
        #expect(decision.runningIssueId == "a")
    }

    @Test func mixedBatchHandlesStopThenStartThenUpdate() {
        let a = issue(id: "a")
        let b = issue(id: "b", title: "Updated B")
        let decision = controller.decide(
            transitions: [
                .stopped(a, reason: .stateChanged(.completed)),
                .started(b),
                .updated(b),
            ],
            currentRunningIssueId: "a"
        )
        #expect(decision.commands == [
            .stop(issueId: "a"),
            .start(issue: b),
            .updateDescription(issue: b),
        ])
        #expect(decision.runningIssueId == "b")
    }
}
