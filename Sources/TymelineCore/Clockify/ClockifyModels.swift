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
