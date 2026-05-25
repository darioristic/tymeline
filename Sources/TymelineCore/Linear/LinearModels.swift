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
