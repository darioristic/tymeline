import XCTest
@testable import TymelineCore

final class LinearClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        session = .mock()
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        session = nil
        super.tearDown()
    }

    func testFetchMeReturnsViewer() async throws {
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
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.httpMethod, "POST")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                json
            )
        }

        let client = LinearClient(apiKey: "test-key", urlSession: session)
        let user = try await client.fetchMe()
        XCTAssertEqual(
            user,
            LinearUser(id: "user-1", name: "Test User", email: "test@example.com")
        )
    }

    func testFetchMePropagatesGraphQLErrors() async {
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
        do {
            _ = try await client.fetchMe()
            XCTFail("expected LinearAPIError.graphqlErrors")
        } catch LinearAPIError.graphqlErrors(let messages) {
            XCTAssertEqual(messages, ["Invalid auth", "Try again"])
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testFetchMeThrowsOnNon2xx() async {
        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        let client = LinearClient(apiKey: "key", urlSession: session)
        do {
            _ = try await client.fetchMe()
            XCTFail("expected LinearAPIError.httpStatus")
        } catch LinearAPIError.httpStatus(let code) {
            XCTAssertEqual(code, 401)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testFetchMeThrowsOnMissingData() async {
        let json = "{}".data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                json
            )
        }

        let client = LinearClient(apiKey: "key", urlSession: session)
        do {
            _ = try await client.fetchMe()
            XCTFail("expected LinearAPIError.missingData")
        } catch LinearAPIError.missingData {
            // success
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testRequestBodyContainsViewerQuery() async throws {
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

        guard
            let bodyData = bodyCapture.body,
            let payload = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
            let query = payload["query"] as? String
        else {
            XCTFail("could not read GraphQL body")
            return
        }
        XCTAssertTrue(query.contains("viewer"))
        XCTAssertTrue(query.contains("email"))
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
