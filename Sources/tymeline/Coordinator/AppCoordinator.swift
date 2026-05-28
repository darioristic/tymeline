import Foundation
import Observation
import TymelineCore

struct WorkspaceProjects: Equatable, Sendable {
    var linear: [LinearProject]
    var clockify: [ClockifyProject]
}

@MainActor
@Observable
final class AppCoordinator {
    var snapshots: [WorkspaceSnapshot] = []
    var workspaceProjects: [UUID: WorkspaceProjects] = [:]
    var workspaceMappings: [UUID: [String: String]] = [:]
    var projectsError: [UUID: String] = [:]
    var actionError: String?
    var setupError: String?

    @ObservationIgnored
    var onStateChange: (() -> Void)?

    private let storage: WorkspaceStorage
    private let secretStorage: SecretStorage
    private let notifications: NotificationService
    private let idleMonitor: IdleMonitor
    private var controllers: [UUID: WorkspaceController] = [:]
    private var pollTasks: [UUID: Task<Void, Never>] = [:]

    init(
        storage: WorkspaceStorage,
        secretStorage: SecretStorage,
        notifications: NotificationService = NotificationService(),
        idleMonitor: IdleMonitor = IdleMonitor()
    ) {
        self.storage = storage
        self.secretStorage = secretStorage
        self.notifications = notifications
        self.idleMonitor = idleMonitor
    }

    func bootstrap() async {
        await notifications.requestAuthorization()
        wireIdleMonitor()
        do {
            let workspaces = try await storage.load()
            for workspace in workspaces {
                await migrateKeychainIfNeeded(for: workspace)
                await attachController(for: workspace)
            }
        } catch {
            setupError = "Failed to load workspaces: \(error.localizedDescription)"
        }
    }

    /// One-shot migration: if API keys are still in the system Keychain
    /// (from a build before v0.1.2), copy them into the sandbox-local
    /// SecretStorage and remove the Keychain entry so we never prompt
    /// the user again. Idempotent and silent on missing keys.
    private func migrateKeychainIfNeeded(for workspace: Workspace) async {
        let pairs: [(KeychainHelper.ServiceKind, String)] = [
            (.linear, KeychainHelper.accountName(service: .linear, workspaceId: workspace.id.uuidString)),
            (.clockify, KeychainHelper.accountName(service: .clockify, workspaceId: workspace.id.uuidString)),
        ]
        for (_, account) in pairs {
            if (try? await secretStorage.get(account)) != nil { continue }
            guard let legacy = try? KeychainHelper.getSecret(for: account) else { continue }
            do {
                try await secretStorage.set(legacy, for: account)
                try? KeychainHelper.deleteSecret(for: account)
            } catch {
                // Leave keychain entry alone if write fails - we'll retry next launch.
            }
        }
    }

    private func wireIdleMonitor() {
        idleMonitor.isAnyTimerRunning = { [weak self] in
            self?.firstRunningSnapshot != nil
        }
        idleMonitor.onWarn = { [weak self] away in
            guard let identifier = self?.firstRunningSnapshot?.runningIssueIdentifier else { return }
            self?.notifications.notifyIdleWarn(
                identifier: identifier,
                idleMinutes: Self.minutes(away)
            )
        }
        idleMonitor.onAutoStop = { [weak self] away in
            guard let self else { return }
            let identifier = self.firstRunningSnapshot?.runningIssueIdentifier ?? "?"
            self.notifications.notifyError(
                "Auto-stopped \(identifier) after \(Self.minutes(away)) min idle"
            )
            Task { @MainActor in
                await self.stopAllRunningTimers()
            }
        }
        notifications.onStillActive = { [weak self] in
            self?.idleMonitor.userConfirmedActive()
        }
        notifications.onStopRequested = { [weak self] in
            Task { @MainActor in
                await self?.stopAllRunningTimers()
            }
        }
        idleMonitor.start()
    }

    private static func minutes(_ seconds: TimeInterval) -> Int {
        Int(seconds / 60)
    }

    private func stopAllRunningTimers() async {
        for snapshot in snapshots where snapshot.runningIssueId != nil {
            await stopRunningTimer(workspaceId: snapshot.workspaceId)
        }
    }

    func addWorkspace(name: String, linearKey: String, clockifyKey: String) async throws {
        var workspace = Workspace(name: name)

        let linear = LinearClient(apiKey: linearKey)
        let linearUser = try await linear.fetchMe()
        workspace.linearUserId = linearUser.id

        let clockify = ClockifyClient(apiKey: clockifyKey)
        let clockifyUser = try await clockify.fetchMe()
        workspace.clockifyUserId = clockifyUser.id
        workspace.clockifyWorkspaceId = clockifyUser.activeWorkspace

        let linearAccount = KeychainHelper.accountName(service: .linear, workspaceId: workspace.id.uuidString)
        let clockifyAccount = KeychainHelper.accountName(service: .clockify, workspaceId: workspace.id.uuidString)
        try await secretStorage.set(linearKey, for: linearAccount)
        try await secretStorage.set(clockifyKey, for: clockifyAccount)

        var existing = try await storage.load()
        existing.append(workspace)
        try await storage.save(existing)

        await attachController(for: workspace)
    }

    func loadProjects(for workspaceId: UUID) async {
        guard let controller = controllers[workspaceId] else { return }
        do {
            let (linear, clockify) = try await controller.fetchProjects()
            workspaceProjects[workspaceId] = WorkspaceProjects(linear: linear, clockify: clockify)
            projectsError[workspaceId] = nil
        } catch {
            projectsError[workspaceId] = error.localizedDescription
        }
    }

    /// Toggle the per-workspace "include backlog" filter. Persists to disk,
    /// updates the in-memory controller, and triggers an immediate poll so
    /// the menu / Settings card reflect the new issue set without waiting
    /// for the next scheduled poll tick.
    func setIncludeBacklog(workspaceId: UUID, value: Bool) async {
        guard let controller = controllers[workspaceId] else { return }
        await controller.updateIncludeBacklog(value)

        do {
            var all = try await storage.load()
            if let idx = all.firstIndex(where: { $0.id == workspaceId }) {
                all[idx].includeBacklog = value
                all[idx].updatedAt = Date()
                try await storage.save(all)
            }
        } catch {
            actionError = "Failed to persist backlog setting: \(error.localizedDescription)"
        }

        _ = try? await controller.poll()
    }

    func setProjectMappings(workspaceId: UUID, mappings: [String: String]) async {
        guard let controller = controllers[workspaceId] else { return }
        await controller.updateProjectMappings(mappings)
        workspaceMappings[workspaceId] = mappings

        do {
            var all = try await storage.load()
            if let idx = all.firstIndex(where: { $0.id == workspaceId }) {
                all[idx].projectMappings = mappings
                all[idx].updatedAt = Date()
                try await storage.save(all)
            }
        } catch {
            actionError = "Failed to persist mappings: \(error.localizedDescription)"
        }
    }

    func startTimer(workspaceId: UUID, issue: LinearIssue) async {
        guard let controller = controllers[workspaceId] else { return }
        do {
            try await controller.startTimer(for: issue)
            actionError = nil
            notifications.notifyStarted(identifier: issue.identifier, title: issue.title)
        } catch {
            actionError = error.localizedDescription
            notifications.notifyError("Start \(issue.identifier) failed: \(error.localizedDescription)")
        }
        onStateChange?()
    }

    /// Tears down a workspace: cancels polling, drops all in-memory state,
    /// removes it from on-disk storage, and clears Keychain secrets so the
    /// API keys aren't left behind after the user removes a workspace.
    func removeWorkspace(workspaceId: UUID) async {
        pollTasks[workspaceId]?.cancel()
        pollTasks.removeValue(forKey: workspaceId)
        controllers.removeValue(forKey: workspaceId)

        snapshots.removeAll(where: { $0.workspaceId == workspaceId })
        workspaceProjects.removeValue(forKey: workspaceId)
        workspaceMappings.removeValue(forKey: workspaceId)
        projectsError.removeValue(forKey: workspaceId)

        do {
            var all = try await storage.load()
            all.removeAll(where: { $0.id == workspaceId })
            try await storage.save(all)
        } catch {
            actionError = "Failed to update storage: \(error.localizedDescription)"
        }

        let linearAccount = KeychainHelper.accountName(service: .linear, workspaceId: workspaceId.uuidString)
        let clockifyAccount = KeychainHelper.accountName(service: .clockify, workspaceId: workspaceId.uuidString)
        try? await secretStorage.delete(linearAccount)
        try? await secretStorage.delete(clockifyAccount)
        // Best-effort sweep of any legacy Keychain leftovers from older versions.
        try? KeychainHelper.deleteSecret(for: linearAccount)
        try? KeychainHelper.deleteSecret(for: clockifyAccount)

        onStateChange?()
    }

    func stopRunningTimer(workspaceId: UUID) async {
        guard let controller = controllers[workspaceId] else { return }
        let stoppedSnapshot = snapshots.first(where: { $0.workspaceId == workspaceId })
        let stoppedIdentifier = stoppedSnapshot?.runningIssueIdentifier
        let stoppedStartedAt = stoppedSnapshot?.runningStartedAt

        do {
            try await controller.stopRunningTimer()
            actionError = nil
            if let identifier = stoppedIdentifier {
                let elapsed = stoppedStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                notifications.notifyStopped(identifier: identifier, duration: elapsed)
            }
        } catch {
            actionError = error.localizedDescription
            notifications.notifyError("Stop failed: \(error.localizedDescription)")
        }
        onStateChange?()
    }

    var firstRunningSnapshot: WorkspaceSnapshot? {
        snapshots.first(where: { $0.runningIssueId != nil })
    }

    var hasErrorSnapshot: Bool {
        snapshots.contains(where: { $0.lastErrorDescription != nil })
    }

    // MARK: - Private

    private func attachController(for workspace: Workspace) async {
        let linearAccount = KeychainHelper.accountName(service: .linear, workspaceId: workspace.id.uuidString)
        let clockifyAccount = KeychainHelper.accountName(service: .clockify, workspaceId: workspace.id.uuidString)

        do {
            guard let linearKey = try await secretStorage.get(linearAccount),
                  let clockifyKey = try await secretStorage.get(clockifyAccount) else {
                setupError = "Missing API keys for '\(workspace.name)' - re-add the workspace from Settings."
                return
            }

            let linear = LinearClient(apiKey: linearKey)
            let clockify = ClockifyClient(apiKey: clockifyKey)
            let controller = WorkspaceController(
                workspace: workspace,
                linearClient: linear,
                clockifyClient: clockify
            )

            await controller.setSnapshotHandler { [weak self] snapshot in
                Task { @MainActor in
                    self?.applySnapshot(snapshot)
                }
            }

            controllers[workspace.id] = controller
            workspaceMappings[workspace.id] = workspace.projectMappings

            applySnapshot(
                WorkspaceSnapshot(
                    workspaceId: workspace.id,
                    workspaceName: workspace.name,
                    assignedIssues: [],
                    runningIssueId: nil,
                    runningIssueIdentifier: nil,
                    runningIssueTitle: nil,
                    runningStartedAt: nil,
                    lastErrorDescription: nil,
                    lastPollAt: nil,
                    includeBacklog: workspace.includeBacklog
                )
            )

            await controller.resumeRunningIfAny()

            let task = Task { [controller] in
                await controller.run()
            }
            pollTasks[workspace.id] = task
        } catch {
            setupError = "Failed to load secrets for '\(workspace.name)': \(error.localizedDescription)"
        }
    }

    private func applySnapshot(_ snapshot: WorkspaceSnapshot) {
        if let idx = snapshots.firstIndex(where: { $0.workspaceId == snapshot.workspaceId }) {
            if snapshots[idx] == snapshot { return }
            snapshots[idx] = snapshot
        } else {
            snapshots.append(snapshot)
        }
        onStateChange?()
    }
}
