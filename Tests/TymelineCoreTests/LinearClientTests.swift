import Testing
import Foundation
@testable import TymelineCore

@Suite("LinearClient", .serialized)
final class LinearClientTests {
    let session: URLSession

    init() {
        session = .mock()
    }

    deinit {
        MockURLProtocol.requestHandler = nil
    }

    @Test func fetchMeReturnsViewer() async throws {
        let json = """
        {
          "data": {
            "viewer": {
              "id": "user-1",
              "name": "Test User",
              "email": "test@example.com"
            }
          }
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "test-key")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.httpMethod == "POST")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                json
            )
        }

        let client = LinearClient(apiKey: "test-key", urlSession: session)
        let user = try await client.fetchMe()
        #expect(user == LinearUser(id: "user-1", name: "Test User", email: "test@example.com"))
    }

    @Test func fetchMePropagatesGraphQLErrors() async throws {
        let json = """
        {
          "errors": [{"message": "Invalid auth"}, {"message": "Try again"}]
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                json
            )
        }

        let client = LinearClient(apiKey: "key", urlSession: session)
        await #expect(throws: LinearAPIError.graphqlErrors(["Invalid auth", "Try again"])) {
            _ = try await client.fetchMe()
        }
    }

    @Test func fetchMeThrowsOnNon2xx() async throws {
        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        let client = LinearClient(apiKey: "key", urlSession: session)
        await #expect(throws: LinearAPIError.httpStatus(401)) {
            _ = try await client.fetchMe()
        }
    }

    @Test func fetchMeThrowsOnMissingData() async throws {
        let json = "{}".data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                json
            )
        }

        let client = LinearClient(apiKey: "key", urlSession: session)
        await #expect(throws: LinearAPIError.missingData) {
            _ = try await client.fetchMe()
        }
    }

    @Test func requestBodyContainsViewerQuery() async throws {
        let json = """
        {"data": {"viewer": {"id": "x", "name": "y", "email": "z@w"}}}
        """.data(using: .utf8)!

        let bodyCapture = BodyCapture()

        MockURLProtocol.requestHandler = { request in
            if let stream = request.httpBodyStream {
                bodyCapture.body = Self.readStream(stream)
            } else {
                bodyCapture.body = request.httpBody
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                json
            )
        }

        let client = LinearClient(apiKey: "key", urlSession: session)
        _ = try await client.fetchMe()

        let bodyData = try #require(bodyCapture.body)
        let payload = try #require(
            try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )
        let query = try #require(payload["query"] as? String)
        #expect(query.contains("viewer"))
        #expect(query.contains("email"))
    }

    private static func readStream(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buffer, maxLength: bufferSize)
            if n > 0 { data.append(buffer, count: n) }
            if n <= 0 { break }
        }
        return data
    }

    private final class BodyCapture: @unchecked Sendable {
        var body: Data?
    }
}
