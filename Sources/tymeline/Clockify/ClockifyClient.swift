import Foundation

enum ClockifyAPIError: Error, LocalizedError {
    case invalidResponse
    case httpStatus(Int, body: String?)

    var errorDescription: String? {
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

actor ClockifyClient {
    private let baseURL = URL(string: "https://api.clockify.me/api/v1")!
    private let apiKey: String
    private let urlSession: URLSession

    init(apiKey: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    func fetchMe() async throws -> ClockifyUser {
        var request = URLRequest(url: baseURL.appendingPathComponent("user"))
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClockifyAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClockifyAPIError.httpStatus(
                httpResponse.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        }

        return try JSONDecoder().decode(ClockifyUser.self, from: data)
    }
}
