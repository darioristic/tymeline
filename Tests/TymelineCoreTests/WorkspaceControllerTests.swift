import Testing
import Foundation
@testable import TymelineCore

@Suite("WorkspaceController", .serialized)
final class WorkspaceControllerTests {
    let linearSession: URLSession
    let clockifySession: URLSession

    init() {
        MockURLProtocol.suiteLock.lock()
        MockURLProtocol.requestHandler = nil
        linearSession = .mock()
        clockifySession = .mock()
    }

    deinit {
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.suiteLock.unlock()
    }

    private func makeController(
        linearUserId: String? = "lin-user-me",
        clockifyWorkspaceId: String? = "ck-ws-1",
        clockifyUserId: String? = "ck-user-me"
    ) -> WorkspaceController {
        let workspace = Workspace(
            name: "Test",
            linearUserId: linearUserId,
            clockifyWorkspaceId: clockifyWorkspaceId,
            clockifyUserId: clockifyUserId
        )
        let linear = LinearClient(apiKey: "lin-key", urlSession: linearSession)
        let clockify = ClockifyClient(apiKey: "ck-key", urlSession: clockifySession)
        return WorkspaceController(
            workspace: workspace,
            linearClient: linear,
            clockifyClient: clockify
        )
    }

    @Test func pollThrowsIfLinearUserIdNotResolved() async {
        let controller = makeController(linearUserId: nil)
        await #expect(throws: WorkspaceControllerError.linearUserNotResolved) {
            _ = try await controller.poll()
        }
    }

    @Test func pollThrowsIfClockifyWorkspaceIdNotResolved() async {
        let controller = makeController(clockifyWorkspaceId: nil)
        await #expect(throws: WorkspaceControllerError.clockifyWorkspaceNotResolved) {
            _ = try await controller.poll()
        }
    }

    @Test func resolveIdentityPopulatesAllIds() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            let path = url.path
            let host = url.host ?? ""

            if host.contains("linear") {
                // Linear fetchMe returns viewer
                let json = """
                {"data": {"viewer": {"id": "lin-resolved", "name": "Me", "email": "me@x.com"}}}
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            if host.contains("clockify") && path.hasSuffix("/user") {
                let json = """
                {"id": "ck-resolved", "email": "me@x.com", "name": "Me", "activeWorkspace": "ck-ws-resolved"}
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            Issue.record("Unexpected request: \(request.httpMethod ?? "?") \(url)")
            return (HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }

        let controller = makeController(linearUserId: nil, clockifyWorkspaceId: nil, clockifyUserId: nil)
        try await controller.resolveIdentity()

        let workspace = await controller.workspace
        #expect(workspace.linearUserId == "lin-resolved")
        #expect(workspace.clockifyUserId == "ck-resolved")
        #expect(workspace.clockifyWorkspaceId == "ck-ws-resolved")
    }

    @Test func resolveIdentityIsIdempotentWhenAlreadySet() async throws {
        var fetchCount = 0
        let counter = Counter()

        MockURLProtocol.requestHandler = { request in
            counter.increment()
            let url = request.url!
            return (HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }

        let controller = makeController()
        try await controller.resolveIdentity()
        _ = fetchCount
        #expect(counter.value == 0)  // no HTTP calls made
    }

    @Test func pollWithFirstStartedIssueCallsStartTimer() async throws {
        let interactions = InteractionLog()

        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            let method = request.httpMethod ?? "?"
            interactions.append("\(method) \(url.host ?? "")\(url.path)")

            if url.host?.contains("linear") == true {
                let json = """
                {
                  "data": {
                    "viewer": {
                      "assignedIssues": {
                        "nodes": [
                          {
                            "id": "iss-1",
                            "identifier": "ENG-100",
                            "title": "Active task",
                            "state": {"id": "st", "name": "In Progress", "type": "started"},
                            "assignee": {"id": "lin-user-me"},
                            "project": {"id": "proj-1"},
                            "updatedAt": "2026-05-25T10:00:00.000Z"
                          }
                        ]
                      }
                    }
                  }
                }
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }

            if url.host?.contains("clockify") == true && method == "POST" {
                let json = """
                {
                  "id": "te-1",
                  "description": "ENG-100: Active task",
                  "projectId": null,
                  "userId": "ck-user-me",
                  "workspaceId": "ck-ws-1",
                  "timeInterval": {"start": "2026-05-25T10:00:00Z", "end": null}
                }
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            }

            Issue.record("Unexpected request: \(method) \(url)")
            return (HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }

        let controller = makeController()
        let decision = try await controller.poll()

        #expect(decision.runningIssueId == "iss-1")
        #expect(decision.commands.count == 1)
        if case .start(let issue) = decision.commands[0] {
            #expect(issue.identifier == "ENG-100")
        } else {
            Issue.record("expected start command")
        }

        let snapshot = await controller.lastSnapshot
        let running = await controller.currentRunningIssueId
        #expect(snapshot.count == 1)
        #expect(running == "iss-1")

        #expect(interactions.values.contains { $0.contains("POST") && $0.contains("clockify") })
    }

    @Test func subsequentPollWithIssueCompletedCallsStopTimer() async throws {
        let interactions = InteractionLog()
        let pollNumber = Counter()

        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            let method = request.httpMethod ?? "?"
            interactions.append("\(method) \(url.host ?? "")\(url.path)")

            if url.host?.contains("linear") == true {
                pollNumber.increment()
                let stateType = pollNumber.value == 1 ? "started" : "completed"
                let json = """
                {
                  "data": {
                    "viewer": {
                      "assignedIssues": {
                        "nodes": [
                          {
                            "id": "iss-1",
                            "identifier": "ENG-100",
                            "title": "Task",
                            "state": {"id": "st", "name": "State", "type": "\(stateType)"},
                            "assignee": {"id": "lin-user-me"},
                            "project": null,
                            "updatedAt": "2026-05-25T10:00:00.000Z"
                          }
                        ]
                      }
                    }
                  }
                }
                """.data(using: .utf8)!
                // Note: second poll will filter out 'completed' state in real API
                // because of the query filter, but we keep it in the response for
                // this test to verify the .stateChanged transition path.
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }

            if url.host?.contains("clockify") == true && method == "POST" {
                let json = """
                {
                  "id": "te-1",
                  "description": "ENG-100: Task",
                  "projectId": null,
                  "userId": "ck-user-me",
                  "workspaceId": "ck-ws-1",
                  "timeInterval": {"start": "2026-05-25T10:00:00Z", "end": null}
                }
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            }

            if url.host?.contains("clockify") == true && method == "PATCH" {
                let json = """
                {
                  "id": "te-1",
                  "description": "ENG-100: Task",
                  "projectId": null,
                  "userId": "ck-user-me",
                  "workspaceId": "ck-ws-1",
                  "timeInterval": {"start": "2026-05-25T10:00:00Z", "end": "2026-05-25T11:00:00Z"}
                }
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }

            Issue.record("Unexpected request: \(method) \(url)")
            return (HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }

        let controller = makeController()

        // First poll - issue is started, timer starts
        let firstDecision = try await controller.poll()
        #expect(firstDecision.runningIssueId == "iss-1")

        // Second poll - issue is completed, timer should stop
        let secondDecision = try await controller.poll()
        #expect(secondDecision.runningIssueId == nil)
        #expect(secondDecision.commands.count == 1)
        if case .stop(let issueId) = secondDecision.commands[0] {
            #expect(issueId == "iss-1")
        } else {
            Issue.record("expected stop command")
        }

        let running = await controller.currentRunningIssueId
        #expect(running == nil)

        let patches = interactions.values.filter { $0.contains("PATCH") }
        #expect(patches.count == 1)
    }

    // Simple thread-safe collectors for handler-side observation.
    private final class InteractionLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [String] = []
        var values: [String] {
            lock.lock(); defer { lock.unlock() }
            return _values
        }
        func append(_ v: String) {
            lock.lock(); defer { lock.unlock() }
            _values.append(v)
        }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: Int = 0
        var value: Int {
            lock.lock(); defer { lock.unlock() }
            return _value
        }
        func increment() {
            lock.lock(); defer { lock.unlock() }
            _value += 1
        }
    }
}
