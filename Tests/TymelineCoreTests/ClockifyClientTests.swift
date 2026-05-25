import Testing
import Foundation
@testable import TymelineCore

@Suite("ClockifyClient", .serialized)
final class ClockifyClientTests {
    let session: URLSession

    init() {
        session = .mock()
    }

    deinit {
        MockURLProtocol.requestHandler = nil
    }

    @Test func fetchMeReturnsUser() async throws {
        let json = """
        {
          "id": "u-1",
          "email": "x@y.com",
          "name": "Test",
          "activeWorkspace": "ws-1"
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "ck-key")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/v1/user")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                json
            )
        }

        let client = ClockifyClient(apiKey: "ck-key", urlSession: session)
        let user = try await client.fetchMe()
        #expect(user == ClockifyUser(id: "u-1", email: "x@y.com", name: "Test", activeWorkspace: "ws-1"))
    }

    @Test func fetchMePropagatesHTTPErrorWithBody() async throws {
        let body = #"{"error": "unauthorized"}"#.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        let client = ClockifyClient(apiKey: "key", urlSession: session)
        await #expect(
            throws: ClockifyAPIError.httpStatus(401, body: #"{"error": "unauthorized"}"#)
        ) {
            _ = try await client.fetchMe()
        }
    }

    @Test func fetchMeThrowsOnMalformedJSON() async throws {
        let json = #"{"id": "incomplete"}"#.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                json
            )
        }

        let client = ClockifyClient(apiKey: "key", urlSession: session)
        await #expect(throws: DecodingError.self) {
            _ = try await client.fetchMe()
        }
    }
}
