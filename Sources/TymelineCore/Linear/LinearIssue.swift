import Foundation

/// Linear's workflow state types. Mirrors the `state.type` enum returned by
/// the Linear GraphQL API. We care most about `started` (work is happening,
/// timer should run) vs everything else.
public enum LinearIssueStateType: String, Codable, Equatable, Sendable {
    case backlog
    case unstarted
    case started
    case completed
    case canceled
    case triage
}

/// One Linear issue. Subset of fields we actually use for polling/transitions.
public struct LinearIssue: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let identifier: String       // e.g. "ENG-153"
    public let title: String
    public let stateType: LinearIssueStateType
    public let stateName: String        // "In Progress", "Done", etc.
    public let assigneeId: String?
    public let projectId: String?
    public let parentId: String?        // id of parent issue if this is a sub-issue
    public let updatedAt: Date

    public init(
        id: String,
        identifier: String,
        title: String,
        stateType: LinearIssueStateType,
        stateName: String,
        assigneeId: String?,
        projectId: String?,
        parentId: String? = nil,
        updatedAt: Date
    ) {
        self.id = id
        self.identifier = identifier
        self.title = title
        self.stateType = stateType
        self.stateName = stateName
        self.assigneeId = assigneeId
        self.projectId = projectId
        self.parentId = parentId
        self.updatedAt = updatedAt
    }

    /// Convenience: state is `.started` regardless of assignee.
    public var isStarted: Bool {
        stateType == .started
    }

    /// "I should be tracking time on this issue right now": state is started
    /// AND this user is the assignee.
    public func isActive(for userId: String) -> Bool {
        stateType == .started && assigneeId == userId
    }
}
