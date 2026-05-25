import Testing
import Foundation
@testable import TymelineCore

@Suite("LinearClient.fetchAssignedIssues", .serialized)
final class LinearAssignedIssuesTests {
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

    @Test func returnsParsedIssues() async throws {
        let json = """
        {
          "data": {
            "viewer": {
              "assignedIssues": {
                "nodes": [
                  {
                    "id": "iss-1",
                    "identifier": "ENG-153",
                    "title": "OpenShift SSL setup",
                    "state": { "id": "st-1", "name": "In Progress", "type": "started" },
                    "assignee": { "id": "user-me" },
                    "project": { "id": "proj-1" },
                    "updatedAt": "2026-05-25T10:00:00.000Z"
                  },
                  {
                    "id": "iss-2",
                    "identifier": "ENG-160",
                    "title": "Review PR",
                    "state": { "id": "st-2", "name": "Todo", "type": "unstarted" },
                    "assignee": { "id": "user-me" },
                    "project": null,
                    "updatedAt": "2026-05-25T09:00:00.000Z"
                  }
                ]
              }
            }
          }
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                json
            )
        }

        let client = LinearClient(apiKey: "key", urlSession: session)
        let issues = try await client.fetchAssignedIssues()

        #expect(issues.count == 2)

        let started = issues[0]
        #expect(started.id == "iss-1")
        #expect(started.identifier == "ENG-153")
        #expect(started.title == "OpenShift SSL setup")
        #expect(started.stateType == .started)
        #expect(started.stateName == "In Progress")
        #expect(started.assigneeId == "user-me")
        #expect(started.projectId == "proj-1")
        #expect(started.isActiveForMe)

        let unstarted = issues[1]
        #expect(unstarted.identifier == "ENG-160")
        #expect(unstarted.stateType == .unstarted)
        #expect(unstarted.projectId == nil)
        #expect(!unstarted.isActiveForMe)
    }

    @Test func handlesEmptyIssueList() async throws {
        let json = """
        {
          "data": {
            "viewer": {
              "assignedIssues": {
                "nodes": []
              }
            }
          }
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                json
            )
        }

        let client = LinearClient(apiKey: "key", urlSession: session)
        let issues = try await client.fetchAssignedIssues()
        #expect(issues.isEmpty)
    }

    @Test func handlesIssueWithoutAssignee() async throws {
        let json = """
        {
          "data": {
            "viewer": {
              "assignedIssues": {
                "nodes": [
                  {
                    "id": "iss-1",
                    "identifier": "ENG-1",
                    "title": "Orphan",
                    "state": { "id": "st-1", "name": "Todo", "type": "unstarted" },
                    "assignee": null,
                    "project": null,
                    "updatedAt": "2026-05-25T10:00:00.000Z"
                  }
                ]
              }
            }
          }
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                json
            )
        }

        let client = LinearClient(apiKey: "key", urlSession: session)
        let issues = try await client.fetchAssignedIssues()
        #expect(issues.count == 1)
        #expect(issues[0].assigneeId == nil)
        #expect(!issues[0].isActiveForMe)
    }

    @Test func queryFiltersForUnstartedAndStarted() async throws {
        let json = """
        {"data": {"viewer": {"assignedIssues": {"nodes": []}}}}
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
        _ = try await client.fetchAssignedIssues()

        let bodyData = try #require(bodyCapture.body)
        let payload = try #require(
            try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )
        let query = try #require(payload["query"] as? String)
        #expect(query.contains("assignedIssues"))
        #expect(query.contains("unstarted"))
        #expect(query.contains("started"))
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
