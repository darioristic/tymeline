import XCTest
@testable import TymelineCore

final class ClockifyClientTests: XCTestCase {
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

    func testFetchMeReturnsUser() async throws {
        let json = """
        {
          "id": "u-1",
          "email": "x@y.com",
          "name": "Test",
          "activeWorkspace": "ws-1"
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Key"), "ck-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/user")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                json
            )
        }

        let client = ClockifyClient(apiKey: "ck-key", urlSession: session)
        let user = try await client.fetchMe()
        XCTAssertEqual(
            user,
            ClockifyUser(id: "u-1", email: "x@y.com", name: "Test", activeWorkspace: "ws-1")
        )
    }

    func testFetchMePropagatesHTTPErrorWithBody() async {
        let body = #"{"error": "unauthorized"}"#.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        let client = ClockifyClient(apiKey: "key", urlSession: session)
        do {
            _ = try await client.fetchMe()
            XCTFail("expected ClockifyAPIError.httpStatus")
        } catch ClockifyAPIError.httpStatus(let code, let bodyString) {
            XCTAssertEqual(code, 401)
            XCTAssertEqual(bodyString, #"{"error": "unauthorized"}"#)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testFetchMeThrowsOnMalformedJSON() async {
        let json = #"{"id": "incomplete"}"#.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                json
            )
        }

        let client = ClockifyClient(apiKey: "key", urlSession: session)
        do {
            _ = try await client.fetchMe()
            XCTFail("expected decoding error")
        } catch is DecodingError {
            // success
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}
