import Foundation

struct ClockifyUser: Decodable, Equatable, Sendable {
    let id: String
    let email: String
    let name: String
    let activeWorkspace: String
}
