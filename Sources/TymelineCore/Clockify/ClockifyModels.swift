import Foundation

public struct ClockifyUser: Decodable, Equatable, Sendable {
    public let id: String
    public let email: String
    public let name: String
    public let activeWorkspace: String

    public init(id: String, email: String, name: String, activeWorkspace: String) {
        self.id = id
        self.email = email
        self.name = name
        self.activeWorkspace = activeWorkspace
    }
}

public struct ClockifyTimeEntry: Decodable, Equatable, Sendable {
    public let id: String
    public let description: String
    public let projectId: String?
    public let userId: String
    public let workspaceId: String
    public let timeInterval: Interval

    public struct Interval: Decodable, Equatable, Sendable {
        public let start: String        // ISO 8601 string
        public let end: String?         // nil while the timer is running

        public init(start: String, end: String?) {
            self.start = start
            self.end = end
        }
    }

    public init(
        id: String,
        description: String,
        projectId: String?,
        userId: String,
        workspaceId: String,
        timeInterval: Interval
    ) {
        self.id = id
        self.description = description
        self.projectId = projectId
        self.userId = userId
        self.workspaceId = workspaceId
        self.timeInterval = timeInterval
    }

    public var isRunning: Bool { timeInterval.end == nil }
}
