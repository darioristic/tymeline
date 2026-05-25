import Foundation

public enum WorkspaceControllerError: Error, LocalizedError, Equatable {
    case linearUserNotResolved
    case clockifyWorkspaceNotResolved
    case clockifyUserNotResolved
    case projectMappingMissing(linearIdentifier: String, linearProjectName: String?)

    public var errorDescription: String? {
        switch self {
        case .linearUserNotResolved:
            return "Linear user ID not resolved yet - call resolveIdentity()"
        case .clockifyWorkspaceNotResolved:
            return "Clockify workspace ID not resolved yet - call resolveIdentity()"
        case .clockifyUserNotResolved:
            return "Clockify user ID not resolved yet - call resolveIdentity()"
        case .projectMappingMissing(let identifier, let name):
            if let name {
                return "No Clockify project mapped for Linear project '\(name)' (\(identifier)) - configure in Settings > Projects"
            }
            return "No Clockify project mapped for \(identifier) - configure in Settings > Projects"
        }
    }
}

/// Immutable snapshot of a WorkspaceController's live state. Safe to bridge
/// from actor isolation to @Observable view-model code.
public struct WorkspaceSnapshot: Sendable, Equatable {
    public let workspaceId: UUID
    public let workspaceName: String
    public let assignedIssues: [LinearIssue]
    public let runningIssueId: String?
    public let runningIssueIdentifier: String?
    public let runningIssueTitle: String?
    public let runningStartedAt: Date?
    public let lastErrorDescription: String?
    public let lastPollAt: Date?

    public init(
        workspaceId: UUID,
        workspaceName: String,
        assignedIssues: [LinearIssue],
        runningIssueId: String?,
        runningIssueIdentifier: String?,
        runningIssueTitle: String?,
        runningStartedAt: Date?,
        lastErrorDescription: String?,
        lastPollAt: Date?
    ) {
        self.workspaceId = workspaceId
        self.workspaceName = workspaceName
        self.assignedIssues = assignedIssues
        self.runningIssueId = runningIssueId
        self.runningIssueIdentifier = runningIssueIdentifier
        self.runningIssueTitle = runningIssueTitle
        self.runningStartedAt = runningStartedAt
        self.lastErrorDescription = lastErrorDescription
        self.lastPollAt = lastPollAt
    }
}

/// Orchestrates one workspace.
///
/// Two modes of operation:
/// - poll(): fetches assigned Linear issues and refreshes the snapshot. Does
///   NOT start/stop timers automatically. Called periodically by run().
/// - startTimer(for:) / stopRunningTimer(): manual user actions. Resolves
///   the Clockify project via workspace.projectMappings, throws if missing.
///
/// The TransitionDetector / AutoTimerController types in TymelineCore are
/// preserved for a future "auto mode" toggle but are no longer wired into
/// the default poll path.
public actor WorkspaceController {
    public private(set) var workspace: Workspace
    public private(set) var assignedIssues: [LinearIssue] = []
    public private(set) var currentRunningIssueId: String?
    public private(set) var lastError: Error?
    public private(set) var lastPollAt: Date?
    public private(set) var isRunning: Bool = false

    private let linearClient: LinearClient
    private let clockifyClient: ClockifyClient
    private var onSnapshotChange: (@Sendable (WorkspaceSnapshot) -> Void)?
    private var runningIssueMetadata: (identifier: String, title: String)?
    private var runningStartedAt: Date?
    private let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoParserNoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public init(
        workspace: Workspace,
        linearClient: LinearClient,
        clockifyClient: ClockifyClient
    ) {
        self.workspace = workspace
        self.linearClient = linearClient
        self.clockifyClient = clockifyClient
    }

    /// Install (or replace) a handler invoked after every snapshot change
    /// (poll, manual start/stop, project-mapping update).
    public func setSnapshotHandler(_ handler: (@Sendable (WorkspaceSnapshot) -> Void)?) {
        self.onSnapshotChange = handler
    }

    public func snapshot() -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            workspaceId: workspace.id,
            workspaceName: workspace.name,
            assignedIssues: assignedIssues,
            runningIssueId: currentRunningIssueId,
            runningIssueIdentifier: runningIssueMetadata?.identifier,
            runningIssueTitle: runningIssueMetadata?.title,
            runningStartedAt: runningStartedAt,
            lastErrorDescription: lastError?.localizedDescription,
            lastPollAt: lastPollAt
        )
    }

    /// Fetch user IDs from both APIs and cache on the workspace. Idempotent.
    public func resolveIdentity() async throws {
        if workspace.linearUserId == nil {
            let me = try await linearClient.fetchMe()
            workspace.linearUserId = me.id
            workspace.updatedAt = Date()
        }
        if workspace.clockifyUserId == nil || workspace.clockifyWorkspaceId == nil {
            let me = try await clockifyClient.fetchMe()
            workspace.clockifyUserId = me.id
            workspace.clockifyWorkspaceId = me.activeWorkspace
            workspace.updatedAt = Date()
        }
    }

    /// Refresh the list of assigned issues. Does not touch timers.
    @discardableResult
    public func poll() async throws -> [LinearIssue] {
        guard workspace.linearUserId != nil else {
            throw WorkspaceControllerError.linearUserNotResolved
        }
        do {
            let issues = try await linearClient.fetchAssignedIssues()
            assignedIssues = issues
            lastPollAt = Date()
            lastError = nil
            onSnapshotChange?(snapshot())
            return issues
        } catch {
            lastError = error
            onSnapshotChange?(snapshot())
            throw error
        }
    }

    public func run() async {
        isRunning = true
        defer { isRunning = false }

        while !Task.isCancelled && isRunning {
            do {
                try await poll()
            } catch {
                // lastError already set by poll()
            }
            let interval = UInt64(max(1, workspace.pollIntervalSeconds)) * 1_000_000_000
            try? await Task.sleep(nanoseconds: interval)
        }
    }

    public func stop() {
        isRunning = false
    }

    /// Manually start a Clockify timer for the given issue. Resolves the
    /// Clockify project via `workspace.projectMappings`. Throws if no
    /// mapping is configured for the issue's Linear project.
    public func startTimer(for issue: LinearIssue) async throws {
        guard let clockifyWorkspaceId = workspace.clockifyWorkspaceId else {
            throw WorkspaceControllerError.clockifyWorkspaceNotResolved
        }

        let clockifyProjectId: String
        if let linearProjectId = issue.projectId,
           let mapped = workspace.projectMappings[linearProjectId] {
            clockifyProjectId = mapped
        } else {
            throw WorkspaceControllerError.projectMappingMissing(
                linearIdentifier: issue.identifier,
                linearProjectName: nil
            )
        }

        let entry = try await clockifyClient.startTimer(
            workspaceId: clockifyWorkspaceId,
            description: "\(issue.identifier): \(issue.title)",
            projectId: clockifyProjectId
        )
        currentRunningIssueId = issue.id
        runningIssueMetadata = (issue.identifier, issue.title)
        runningStartedAt = parseISO(entry.timeInterval.start) ?? Date()
        onSnapshotChange?(snapshot())
    }

    public func stopRunningTimer() async throws {
        guard let clockifyWorkspaceId = workspace.clockifyWorkspaceId,
              let clockifyUserId = workspace.clockifyUserId else {
            throw WorkspaceControllerError.clockifyWorkspaceNotResolved
        }

        _ = try await clockifyClient.stopRunningTimer(
            workspaceId: clockifyWorkspaceId,
            userId: clockifyUserId
        )
        currentRunningIssueId = nil
        runningIssueMetadata = nil
        runningStartedAt = nil
        onSnapshotChange?(snapshot())
    }

    private func parseISO(_ string: String) -> Date? {
        isoParser.date(from: string) ?? isoParserNoFractional.date(from: string)
    }

    /// Concurrent fetch of Linear and Clockify project lists for the
    /// Settings > Projects mapping UI.
    public func fetchProjects() async throws -> (linear: [LinearProject], clockify: [ClockifyProject]) {
        guard let clockifyWorkspaceId = workspace.clockifyWorkspaceId else {
            throw WorkspaceControllerError.clockifyWorkspaceNotResolved
        }
        async let linear = linearClient.fetchProjects()
        async let clockify = clockifyClient.fetchProjects(workspaceId: clockifyWorkspaceId)
        return try await (linear, clockify)
    }

    /// Replace the workspace's project mappings. Caller (AppCoordinator) is
    /// responsible for persisting via WorkspaceStorage.
    public func updateProjectMappings(_ mappings: [String: String]) {
        workspace.projectMappings = mappings
        workspace.updatedAt = Date()
        onSnapshotChange?(snapshot())
    }
}
