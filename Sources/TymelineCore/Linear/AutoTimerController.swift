import Foundation

/// An imperative timer action that should be applied to Clockify.
public enum TimerCommand: Equatable, Sendable {
    case start(issue: LinearIssue)
    case stop(issueId: String)
    case updateDescription(issue: LinearIssue)
}

public struct AutoTimerDecision: Equatable, Sendable {
    public let commands: [TimerCommand]
    public let runningIssueId: String?

    public init(commands: [TimerCommand], runningIssueId: String?) {
        self.commands = commands
        self.runningIssueId = runningIssueId
    }
}

/// Stateless decision-maker: given the currently-running issue (if any) and a
/// batch of detected transitions, returns the timer commands to apply and the
/// new running issue id.
///
/// Rules (per DESIGN.md section 4.3 "last status change wins"):
/// - If multiple `.started` transitions arrive in the same batch, the last one
///   wins and intermediate starts are skipped to avoid timer churn.
/// - A new `.started` for a different issue implicitly stops the currently
///   running one.
/// - `.stopped` for the running issue stops it; `.stopped` for a non-running
///   issue is a no-op.
/// - `.updated` for the running issue refreshes its description; otherwise
///   no-op.
public struct AutoTimerController: Sendable {
    public init() {}

    public func decide(
        transitions: [LinearTransition],
        currentRunningIssueId: String?
    ) -> AutoTimerDecision {
        var commands: [TimerCommand] = []
        var running = currentRunningIssueId

        for transition in transitions {
            if case let .stopped(issue, _) = transition, running == issue.id {
                commands.append(.stop(issueId: issue.id))
                running = nil
            }
        }

        let startedCandidates: [LinearIssue] = transitions.compactMap { transition in
            if case let .started(issue) = transition { return issue }
            return nil
        }

        if let winner = startedCandidates.last {
            if let runningId = running, runningId != winner.id {
                commands.append(.stop(issueId: runningId))
                running = nil
            }
            if running != winner.id {
                commands.append(.start(issue: winner))
                running = winner.id
            }
        }

        for transition in transitions {
            if case let .updated(issue) = transition, running == issue.id {
                commands.append(.updateDescription(issue: issue))
            }
        }

        return AutoTimerDecision(commands: commands, runningIssueId: running)
    }
}
