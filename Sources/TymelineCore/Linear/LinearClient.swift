import Foundation

public enum LinearAPIError: Error, LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case graphqlErrors([String])
    case missingData

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Linear API returned a non-HTTP response"
        case .httpStatus(let code):
            return "Linear API HTTP \(code)"
        case .graphqlErrors(let messages):
            return "Linear GraphQL errors: \(messages.joined(separator: "; "))"
        case .missingData:
            return "Linear API response missing data field"
        }
    }
}

public actor LinearClient {
    public static let defaultEndpoint = URL(string: "https://api.linear.app/graphql")!

    private let endpoint: URL
    private let apiKey: String
    private let urlSession: URLSession

    public init(
        apiKey: String,
        endpoint: URL = LinearClient.defaultEndpoint,
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.urlSession = urlSession
    }

    public func fetchMe() async throws -> LinearUser {
        let query = """
        query Me {
          viewer {
            id
            name
            email
          }
        }
        """
        let response: LinearViewerResponse = try await execute(query: query)
        return response.viewer
    }

    /// Fetches the projects the user has access to. Filters out completed
    /// and canceled projects so the picker stays usable.
    public func fetchProjects() async throws -> [LinearProject] {
        let query = """
        query MyProjects {
          projects(filter: { state: { in: ["started", "planned", "backlog"] } }) {
            nodes {
              id
              name
              color
              state
            }
          }
        }
        """
        let response: LinearProjectsResponse = try await execute(query: query)
        return response.projects.nodes
    }

    /// Fetches issues assigned to the current user. Default filter is
    /// `unstarted` + `started` (the candidate set for the auto-timer); pass
    /// `includeBacklog: true` to also include backlog issues. Ordered by most
    /// recently updated (Linear's default).
    public func fetchAssignedIssues(includeBacklog: Bool = false) async throws -> [LinearIssue] {
        let stateTypes = includeBacklog
            ? "[\"backlog\", \"unstarted\", \"started\"]"
            : "[\"unstarted\", \"started\"]"
        let query = """
        query MyAssignedIssues {
          viewer {
            assignedIssues(
              filter: { state: { type: { in: \(stateTypes) } } }
            ) {
              nodes {
                id
                identifier
                title
                state { id name type }
                assignee { id }
                project { id }
                parent { id }
                updatedAt
              }
            }
          }
        }
        """
        let response: LinearAssignedIssuesResponse = try await execute(query: query)
        return response.toIssues()
    }

    private func execute<T: Decodable & Sendable>(
        query: String,
        variables: [String: Any]? = nil
    ) async throws -> T {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")

        var body: [String: Any] = ["query": query]
        if let variables { body["variables"] = variables }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinearAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LinearAPIError.httpStatus(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LinearGraphQLResponse<T>.self, from: data)

        if let errors = decoded.errors, !errors.isEmpty {
            throw LinearAPIError.graphqlErrors(errors.map(\.message))
        }
        guard let payload = decoded.data else {
            throw LinearAPIError.missingData
        }
        return payload
    }
}
