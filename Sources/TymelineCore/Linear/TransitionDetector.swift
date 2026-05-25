import Foundation

/// What happened to an issue between two consecutive polls.
///
/// "Active" means: state is `.started` AND assignee is the current user. The
/// transitions are emitted from the user's perspective - we don't care about
/// state changes on issues that were never and still aren't active for me.
public enum LinearTransition: Equatable, Sendable {
    /// Issue is now active for me - timer should start.
    case started(LinearIssue)
    /// Issue is no longer active for me - timer should stop.
    case stopped(LinearIssue, reason: LinearStopReason)
    /// Issue stays active, but metadata changed (title rename, etc.) - timer
    /// description may want updating.
    case updated(LinearIssue)
}

public enum LinearStopReason: Equatable, Sendable {
    /// Issue moved to a non-started state (completed, canceled, back to unstarted).
    case stateChanged(LinearIssueStateType)
    /// Assignee was changed away from me.
    case unassigned
    /// Issue disappeared from the fetched set entirely (e.g. archived, deleted,
    /// or moved to a state outside the polled filter).
    case disappeared
}

public struct TransitionDetector: Sendable {
    public init() {}

    /// Compute the transitions between two snapshots of assigned issues.
    /// - Parameters:
    ///   - previous: issues seen on the prior poll, or `[]` on first poll
    ///   - current: issues from the most recent poll
    ///   - userId: Linear user id of the current user (assignee match)
    public func detect(
        previous: [LinearIssue],
        current: [LinearIssue],
        userId: String
    ) -> [LinearTransition] {
        let previousById = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let currentById = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })

        var transitions: [LinearTransition] = []

        // Issues that were active for me previously, and may no longer be.
        for prevIssue in previous where prevIssue.isActive(for: userId) {
            if let currIssue = currentById[prevIssue.id] {
                if currIssue.isActive(for: userId) {
                    if currIssue != prevIssue {
                        transitions.append(.updated(currIssue))
                    }
                } else {
                    let reason: LinearStopReason
                    if currIssue.assigneeId != userId {
                        reason = .unassigned
                    } else {
                        reason = .stateChanged(currIssue.stateType)
                    }
                    transitions.append(.stopped(prevIssue, reason: reason))
                }
            } else {
                transitions.append(.stopped(prevIssue, reason: .disappeared))
            }
        }

        // Issues that are active for me now and weren't before.
        for currIssue in current where currIssue.isActive(for: userId) {
            let wasActive = previousById[currIssue.id]?.isActive(for: userId) ?? false
            if !wasActive {
                transitions.append(.started(currIssue))
            }
        }

        return transitions
    }
}
