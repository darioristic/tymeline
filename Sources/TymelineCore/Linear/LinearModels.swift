import Foundation

public struct LinearUser: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let email: String

    public init(id: String, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
    }
}

struct LinearGraphQLResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let data: T?
    let errors: [LinearGraphQLError]?
}

struct LinearGraphQLError: Decodable, Sendable {
    let message: String
}

struct LinearViewerResponse: Decodable, Sendable {
    let viewer: LinearUser
}

public struct LinearProject: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let color: String?
    public let state: String?

    public init(id: String, name: String, color: String?, state: String?) {
        self.id = id
        self.name = name
        self.color = color
        self.state = state
    }
}

struct LinearProjectsResponse: Decodable, Sendable {
    let projects: ProjectConnection

    struct ProjectConnection: Decodable, Sendable {
        let nodes: [LinearProject]
    }
}

struct LinearAssignedIssuesResponse: Decodable, Sendable {
    let viewer: Viewer

    struct Viewer: Decodable, Sendable {
        let assignedIssues: IssueConnection
    }

    struct IssueConnection: Decodable, Sendable {
        let nodes: [IssueNode]
    }

    struct IssueNode: Decodable, Sendable {
        let id: String
        let identifier: String
        let title: String
        let state: StateNode
        let assignee: AssigneeNode?
        let project: ProjectNode?
        let updatedAt: Date
    }

    struct StateNode: Decodable, Sendable {
        let id: String
        let name: String
        let type: LinearIssueStateType
    }

    struct AssigneeNode: Decodable, Sendable {
        let id: String
    }

    struct ProjectNode: Decodable, Sendable {
        let id: String
    }

    func toIssues() -> [LinearIssue] {
        viewer.assignedIssues.nodes.map { node in
            LinearIssue(
                id: node.id,
                identifier: node.identifier,
                title: node.title,
                stateType: node.state.type,
                stateName: node.state.name,
                assigneeId: node.assignee?.id,
                projectId: node.project?.id,
                updatedAt: node.updatedAt
            )
        }
    }
}
