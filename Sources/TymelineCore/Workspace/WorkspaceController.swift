import Foundation

public enum WorkspaceControllerError: Error, LocalizedError, Equatable {
    case linearUserNotResolved
    case clockifyWorkspaceNotResolved
    case clockifyUserNotResolved

    public var errorDescription: String? {
        switch self {
        case .linearUserNotResolved:
            return "Linear user ID not resolved yet - call resolveIdentity()"
        case .clockifyWorkspaceNotResolved:
            return "Clockify workspace ID not resolved yet - call resolveIdentity()"
        case .clockifyUserNotResolved:
            return "Clockify user ID not resolved yet - call resolveIdentity()"
        }
    }
}

/// Immutable snapshot of a WorkspaceController's live state. Safe to bridge
/// from actor isolation to @Observable view-model code.
public struct WorkspaceSnapshot: Sendable, Equatable {
    public let workspaceId: UUID
    public let workspaceName: String
    public let runningIssueId: String?
    public let runningIssueIdentifier: String?
    public let runningIssueTitle: String?
    public let lastErrorDescription: String?
    public let lastPollAt: Date?

    public init(
        workspaceId: UUID,
        workspaceName: String,
        runningIssueId: String?,
        runningIssueIdentifier: String?,
        runningIssueTitle: String?,
        lastErrorDescription: String?,
        lastPollAt: Date?
    ) {
        self.workspaceId = workspaceId
        self.workspaceName = workspaceName
        self.runningIssueId = runningIssueId
        self.runningIssueIdentifier = runningIssueIdentifier
        self.runningIssueTitle = runningIssueTitle
        self.lastErrorDescription = lastErrorDescription
        self.lastPollAt = lastPollAt
    }
}

/// Orchestrates one workspace's poll loop:
///   LinearClient.fetchAssignedIssues
///     -> TransitionDetector.detect
///     -> AutoTimerController.decide
///     -> ClockifyClient.start/stop timer
///
/// Stateful across polls: keeps the last issue snapshot for diffing and the
/// currently-running Clockify entry id. Tests typically call `poll()`
/// directly; production code calls `run()` which loops with the workspace's
/// configured interval.
public actor WorkspaceController {
    public private(set) var workspace: Workspace
    public private(set) var lastSnapshot: [LinearIssue] = []
    public private(set) var currentRunningIssueId: String?
    public private(set) var lastError: Error?
    public private(set) var lastPollAt: Date?
    public private(set) var isRunning: Bool = false

    private let linearClient: LinearClient
    private let clockifyClient: ClockifyClient
    private let detector: TransitionDetector
    private let controller: AutoTimerController
    private var onSnapshotChange: (@Sendable (WorkspaceSnapshot) -> Void)?
    private var runningIssueMetadata: (identifier: String, title: String)?

    public init(
        workspace: Workspace,
        linearClient: LinearClient,
        clockifyClient: ClockifyClient,
        detector: TransitionDetector = TransitionDetector(),
        controller: AutoTimerController = AutoTimerController()
    ) {
        self.workspace = workspace
        self.linearClient = linearClient
        self.clockifyClient = clockifyClient
        self.detector = detector
        self.controller = controller
    }

    /// Install (or replace) a handler invoked after every poll, including
    /// failed ones. The handler is `@Sendable` so it can hop to MainActor for
    /// UI updates.
    public func setSnapshotHandler(_ handler: (@Sendable (WorkspaceSnapshot) -> Void)?) {
        self.onSnapshotChange = handler
    }

    public func snapshot() -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            workspaceId: workspace.id,
            workspaceName: workspace.name,
            runningIssueId: currentRunningIssueId,
            runningIssueIdentifier: runningIssueMetadata?.identifier,
            runningIssueTitle: runningIssueMetadata?.title,
            lastErrorDescription: lastError?.localizedDescription,
            lastPollAt: lastPollAt
        )
    }

    /// Fetch user IDs from both APIs and cache on the workspace. Idempotent -
    /// re-fetches only fields that are still nil.
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

    /// Run one poll iteration. Returns the timer decision that was applied.
    @discardableResult
    public func poll() async throws -> AutoTimerDecision {
        guard let linearUserId = workspace.linearUserId else {
            throw WorkspaceControllerError.linearUserNotResolved
        }
        guard let clockifyWorkspaceId = workspace.clockifyWorkspaceId else {
            throw WorkspaceControllerError.clockifyWorkspaceNotResolved
        }
        guard let clockifyUserId = workspace.clockifyUserId else {
            throw WorkspaceControllerError.clockifyUserNotResolved
        }

        do {
            let current = try await linearClient.fetchAssignedIssues()
            let transitions = detector.detect(
                previous: lastSnapshot,
                current: current,
                userId: linearUserId
            )
            let decision = controller.decide(
                transitions: transitions,
                currentRunningIssueId: currentRunningIssueId
            )

            for command in decision.commands {
                try await execute(
                    command,
                    clockifyWorkspaceId: clockifyWorkspaceId,
                    clockifyUserId: clockifyUserId
                )
            }

            lastSnapshot = current
            currentRunningIssueId = decision.runningIssueId
            if let runningId = decision.runningIssueId,
               let runningIssue = current.first(where: { $0.id == runningId }) {
                runningIssueMetadata = (runningIssue.identifier, runningIssue.title)
            } else {
                runningIssueMetadata = nil
            }
            lastPollAt = Date()
            lastError = nil
            onSnapshotChange?(snapshot())
            return decision
        } catch {
            lastError = error
            onSnapshotChange?(snapshot())
            throw error
        }
    }

    /// Run the poll loop until the surrounding Task is cancelled or `stop()`
    /// is called. Polls every `workspace.pollIntervalSeconds` and swallows
    /// per-iteration errors (they're surfaced via `lastError`).
    public func run() async {
        isRunning = true
        defer { isRunning = false }

        while !Task.isCancelled && isRunning {
            do {
                try await poll()
            } catch {
                // lastError is already set inside poll()
            }
            let interval = UInt64(max(1, workspace.pollIntervalSeconds)) * 1_000_000_000
            try? await Task.sleep(nanoseconds: interval)
        }
    }

    public func stop() {
        isRunning = false
    }

    // MARK: - Private

    private func execute(
        _ command: TimerCommand,
        clockifyWorkspaceId: String,
        clockifyUserId: String
    ) async throws {
        switch command {
        case .start(let issue):
            _ = try await clockifyClient.startTimer(
                workspaceId: clockifyWorkspaceId,
                description: "\(issue.identifier): \(issue.title)",
                projectId: nil
            )
        case .stop:
            _ = try await clockifyClient.stopRunningTimer(
                workspaceId: clockifyWorkspaceId,
                userId: clockifyUserId
            )
        case .updateDescription:
            // Clockify PUT requires full entry replacement, deferred to later
            // milestone. Description rename is rare and the next start/stop
            // cycle will pick up the new title.
            break
        }
    }
}
