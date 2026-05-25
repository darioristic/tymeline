import Testing
import Foundation
@testable import TymelineCore

@Suite("ClockifyClient", .serialized)
final class ClockifyClientTests {
    let session: URLSession

    init() {
        MockURLProtocol.suiteLock.lock()
        MockURLProtocol.requestHandler = nil
        session = .mock()
    }

    deinit {
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.suiteLock.unlock()
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

    @Test func startTimerReturnsCreatedEntry() async throws {
        let json = """
        {
          "id": "te-1",
          "description": "ENG-153: OpenShift SSL setup",
          "projectId": "proj-1",
          "userId": "u-1",
          "workspaceId": "ws-1",
          "timeInterval": { "start": "2026-05-25T10:00:00Z", "end": null }
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/v1/workspaces/ws-1/time-entries")
            #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "key")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!,
                json
            )
        }

        let client = ClockifyClient(apiKey: "key", urlSession: session)
        let entry = try await client.startTimer(
            workspaceId: "ws-1",
            description: "ENG-153: OpenShift SSL setup",
            projectId: "proj-1",
            start: Date(timeIntervalSince1970: 1_716_633_600)
        )

        #expect(entry.id == "te-1")
        #expect(entry.description == "ENG-153: OpenShift SSL setup")
        #expect(entry.projectId == "proj-1")
        #expect(entry.workspaceId == "ws-1")
        #expect(entry.isRunning)
    }

    @Test func startTimerWithoutProjectIdOmitsField() async throws {
        let json = """
        {
          "id": "te-2",
          "description": "Manual entry",
          "projectId": null,
          "userId": "u-1",
          "workspaceId": "ws-1",
          "timeInterval": { "start": "2026-05-25T10:00:00Z", "end": null }
        }
        """.data(using: .utf8)!

        let bodyCapture = BodyCapture()

        MockURLProtocol.requestHandler = { request in
            if let stream = request.httpBodyStream {
                bodyCapture.body = Self.readStream(stream)
            } else {
                bodyCapture.body = request.httpBody
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!,
                json
            )
        }

        let client = ClockifyClient(apiKey: "key", urlSession: session)
        _ = try await client.startTimer(
            workspaceId: "ws-1",
            description: "Manual entry",
            projectId: nil
        )

        let bodyData = try #require(bodyCapture.body)
        let payload = try #require(
            try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )
        #expect(payload["projectId"] == nil)
        #expect(payload["description"] as? String == "Manual entry")
        #expect(payload["start"] != nil)
    }

    @Test func stopRunningTimerReturnsStoppedEntry() async throws {
        let json = """
        {
          "id": "te-1",
          "description": "ENG-153",
          "projectId": "proj-1",
          "userId": "u-1",
          "workspaceId": "ws-1",
          "timeInterval": { "start": "2026-05-25T10:00:00Z", "end": "2026-05-25T11:00:00Z" }
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url?.path == "/api/v1/workspaces/ws-1/user/u-1/time-entries")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                json
            )
        }

        let client = ClockifyClient(apiKey: "key", urlSession: session)
        let entry = try await client.stopRunningTimer(workspaceId: "ws-1", userId: "u-1")
        let unwrapped = try #require(entry)
        #expect(unwrapped.id == "te-1")
        #expect(!unwrapped.isRunning)
        #expect(unwrapped.timeInterval.end == "2026-05-25T11:00:00Z")
    }

    @Test func stopRunningTimerReturnsNilOn404() async throws {
        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        let client = ClockifyClient(apiKey: "key", urlSession: session)
        let entry = try await client.stopRunningTimer(workspaceId: "ws-1", userId: "u-1")
        #expect(entry == nil)
    }

    @Test func stopRunningTimerThrowsOnOtherErrors() async throws {
        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        let client = ClockifyClient(apiKey: "key", urlSession: session)
        await #expect(throws: ClockifyAPIError.httpStatus(401, body: "")) {
            _ = try await client.stopRunningTimer(workspaceId: "ws-1", userId: "u-1")
        }
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
