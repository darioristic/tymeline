import Foundation

public enum ClockifyAPIError: Error, LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int, body: String?)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Clockify API returned a non-HTTP response"
        case .httpStatus(let code, let body):
            if let body, !body.isEmpty {
                return "Clockify API HTTP \(code): \(body)"
            }
            return "Clockify API HTTP \(code)"
        }
    }
}

public actor ClockifyClient {
    public static let defaultBaseURL = URL(string: "https://api.clockify.me/api/v1")!

    private let baseURL: URL
    private let apiKey: String
    private let urlSession: URLSession
    private let isoFormatter: ISO8601DateFormatter

    public init(
        apiKey: String,
        baseURL: URL = ClockifyClient.defaultBaseURL,
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.urlSession = urlSession
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        self.isoFormatter = formatter
    }

    public func fetchMe() async throws -> ClockifyUser {
        let request = makeRequest(method: "GET", path: "user")
        let (data, _) = try await send(request, accepting: [200])
        return try JSONDecoder().decode(ClockifyUser.self, from: data)
    }

    /// Start a running time entry for the current user in the given workspace.
    /// Returns the newly-created entry.
    public func startTimer(
        workspaceId: String,
        description: String,
        projectId: String?,
        start: Date = Date()
    ) async throws -> ClockifyTimeEntry {
        var body: [String: Any] = [
            "start": isoFormatter.string(from: start),
            "description": description,
        ]
        if let projectId { body["projectId"] = projectId }

        var request = makeRequest(method: "POST", path: "workspaces/\(workspaceId)/time-entries")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await send(request, accepting: [200, 201])
        return try JSONDecoder().decode(ClockifyTimeEntry.self, from: data)
    }

    /// Stop the currently-running time entry for the user. Returns the stopped
    /// entry, or `nil` if there was no running entry (Clockify returns 404).
    public func stopRunningTimer(
        workspaceId: String,
        userId: String,
        end: Date = Date()
    ) async throws -> ClockifyTimeEntry? {
        let body: [String: Any] = ["end": isoFormatter.string(from: end)]

        var request = makeRequest(method: "PATCH", path: "workspaces/\(workspaceId)/user/\(userId)/time-entries")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClockifyAPIError.invalidResponse
        }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            throw ClockifyAPIError.httpStatus(http.statusCode, body: String(data: data, encoding: .utf8))
        }
        return try JSONDecoder().decode(ClockifyTimeEntry.self, from: data)
    }

    // MARK: - Helpers

    private func makeRequest(method: String, path: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func send(
        _ request: URLRequest,
        accepting acceptedStatuses: Set<Int>
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClockifyAPIError.invalidResponse
        }
        guard acceptedStatuses.contains(http.statusCode) else {
            throw ClockifyAPIError.httpStatus(http.statusCode, body: String(data: data, encoding: .utf8))
        }
        return (data, http)
    }
}
