import Foundation

struct LinearUser: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let email: String
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
