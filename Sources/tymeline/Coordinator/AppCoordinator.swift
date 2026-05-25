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
    private var controllers: [UUID: WorkspaceController] = [:]
    private var pollTasks: [UUID: Task<Void, Never>] = [:]

    init(storage: WorkspaceStorage) {
        self.storage = storage
    }

    func bootstrap() async {
        do {
            let workspaces = try await storage.load()
            for workspace in workspaces {
                await attachController(for: workspace)
            }
        } catch {
            setupError = "Failed to load workspaces: \(error.localizedDescription)"
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
        try KeychainHelper.setSecret(linearKey, for: linearAccount)
        try KeychainHelper.setSecret(clockifyKey, for: clockifyAccount)

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
        } catch {
            actionError = error.localizedDescription
        }
        onStateChange?()
    }

    func stopRunningTimer(workspaceId: UUID) async {
        guard let controller = controllers[workspaceId] else { return }
        do {
            try await controller.stopRunningTimer()
            actionError = nil
        } catch {
            actionError = error.localizedDescription
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
            let linearKey = try KeychainHelper.getSecret(for: linearAccount)
            let clockifyKey = try KeychainHelper.getSecret(for: clockifyAccount)

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
                    lastPollAt: nil
                )
            )

            let task = Task { [controller] in
                await controller.run()
            }
            pollTasks[workspace.id] = task
        } catch {
            setupError = "Failed to load Keychain for '\(workspace.name)': \(error.localizedDescription)"
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
