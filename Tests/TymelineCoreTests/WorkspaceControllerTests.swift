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
        clockifyUserId: String? = "ck-user-me",
        projectMappings: [String: String] = [:]
    ) -> WorkspaceController {
        let workspace = Workspace(
            name: "Test",
            linearUserId: linearUserId,
            clockifyWorkspaceId: clockifyWorkspaceId,
            clockifyUserId: clockifyUserId,
            projectMappings: projectMappings
        )
        let linear = LinearClient(apiKey: "lin-key", urlSession: linearSession)
        let clockify = ClockifyClient(apiKey: "ck-key", urlSession: clockifySession)
        return WorkspaceController(
            workspace: workspace,
            linearClient: linear,
            clockifyClient: clockify
        )
    }

    private func issue(
        id: String = "iss-1",
        identifier: String = "ENG-100",
        title: String = "Active task",
        state: LinearIssueStateType = .started,
        projectId: String? = "lin-proj-1"
    ) -> LinearIssue {
        LinearIssue(
            id: id,
            identifier: identifier,
            title: title,
            stateType: state,
            stateName: "In Progress",
            assigneeId: "lin-user-me",
            projectId: projectId,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test func pollThrowsIfLinearUserIdNotResolved() async {
        let controller = makeController(linearUserId: nil)
        await #expect(throws: WorkspaceControllerError.linearUserNotResolved) {
            _ = try await controller.poll()
        }
    }

    @Test func resolveIdentityPopulatesAllIds() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            let host = url.host ?? ""

            if host.contains("linear") {
                let json = """
                {"data": {"viewer": {"id": "lin-resolved", "name": "Me", "email": "me@x.com"}}}
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            if host.contains("clockify") && url.path.hasSuffix("/user") {
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

    @Test func pollFetchesAndUpdatesAssignedIssuesWithoutStartingTimer() async throws {
        let httpCallCount = Counter()

        MockURLProtocol.requestHandler = { request in
            httpCallCount.increment()
            let url = request.url!

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
                            "project": {"id": "lin-proj-1"},
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

            Issue.record("Unexpected request to Clockify - poll should not touch it: \(url)")
            return (HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }

        let controller = makeController()
        let issues = try await controller.poll()

        #expect(issues.count == 1)
        #expect(issues[0].identifier == "ENG-100")

        let running = await controller.currentRunningIssueId
        #expect(running == nil)
        #expect(httpCallCount.value == 1)  // only Linear, not Clockify
    }

    @Test func startTimerThrowsWhenProjectMappingMissing() async {
        let controller = makeController(projectMappings: [:])
        await #expect(throws: WorkspaceControllerError.self) {
            try await controller.startTimer(for: issue())
        }
    }

    @Test func startTimerThrowsWhenIssueHasNoProject() async {
        let controller = makeController(projectMappings: ["lin-proj-1": "ck-proj-1"])
        await #expect(throws: WorkspaceControllerError.self) {
            try await controller.startTimer(for: issue(projectId: nil))
        }
    }

    @Test func startTimerResolvesProjectAndCallsClockifyStart() async throws {
        let interactions = InteractionLog()

        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            interactions.append("\(request.httpMethod ?? "?") \(url.path)")

            let json = """
            {
              "id": "te-1",
              "description": "ENG-100: Active task",
              "projectId": "ck-proj-1",
              "userId": "ck-user-me",
              "workspaceId": "ck-ws-1",
              "timeInterval": {"start": "2026-05-25T10:00:00Z", "end": null}
            }
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let controller = makeController(projectMappings: ["lin-proj-1": "ck-proj-1"])
        try await controller.startTimer(for: issue())

        let running = await controller.currentRunningIssueId
        #expect(running == "iss-1")
        #expect(interactions.values.contains { $0.contains("POST") && $0.contains("/time-entries") })
    }

    @Test func stopRunningTimerCallsClockifyStop() async throws {
        let interactions = InteractionLog()

        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            interactions.append("\(request.httpMethod ?? "?") \(url.path)")

            let json = """
            {
              "id": "te-1",
              "description": "X",
              "projectId": "ck-proj-1",
              "userId": "ck-user-me",
              "workspaceId": "ck-ws-1",
              "timeInterval": {"start": "2026-05-25T10:00:00Z", "end": "2026-05-25T11:00:00Z"}
            }
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let controller = makeController()
        try await controller.stopRunningTimer()

        let running = await controller.currentRunningIssueId
        #expect(running == nil)
        #expect(interactions.values.contains { $0.contains("PATCH") })
    }

    @Test func fetchProjectsReturnsBothLists() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!

            if url.host?.contains("linear") == true {
                let json = """
                {"data": {"projects": {"nodes": [
                  {"id": "lin-proj-1", "name": "Project A", "color": "#FF0000", "state": "started"}
                ]}}}
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            if url.host?.contains("clockify") == true {
                let json = """
                [
                  {"id": "ck-proj-1", "name": "Clockify Project A", "color": "#00FF00", "workspaceId": "ck-ws-1", "clientName": "Acme", "archived": false}
                ]
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            Issue.record("Unexpected request: \(url)")
            return (HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }

        let controller = makeController()
        let (linear, clockify) = try await controller.fetchProjects()

        #expect(linear.count == 1)
        #expect(linear[0].name == "Project A")
        #expect(clockify.count == 1)
        #expect(clockify[0].name == "Clockify Project A")
        #expect(clockify[0].clientName == "Acme")
    }

    @Test func updateProjectMappingsUpdatesWorkspace() async {
        let controller = makeController(projectMappings: ["a": "b"])
        await controller.updateProjectMappings(["a": "b", "c": "d"])
        let workspace = await controller.workspace
        #expect(workspace.projectMappings == ["a": "b", "c": "d"])
    }

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
