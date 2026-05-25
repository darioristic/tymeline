import Foundation

enum LinearAPIError: Error, LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case graphqlErrors([String])
    case missingData

    var errorDescription: String? {
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

actor LinearClient {
    private let endpoint = URL(string: "https://api.linear.app/graphql")!
    private let apiKey: String
    private let urlSession: URLSession

    init(apiKey: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    func fetchMe() async throws -> LinearUser {
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

        let decoded = try JSONDecoder().decode(LinearGraphQLResponse<T>.self, from: data)

        if let errors = decoded.errors, !errors.isEmpty {
            throw LinearAPIError.graphqlErrors(errors.map(\.message))
        }
        guard let payload = decoded.data else {
            throw LinearAPIError.missingData
        }
        return payload
    }
}
