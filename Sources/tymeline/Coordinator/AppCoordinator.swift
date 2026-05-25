import Foundation
import Observation
import TymelineCore

/// Top-level state holder. Owns the `WorkspaceStorage`, the per-workspace
/// `WorkspaceController` actors, and the running poll tasks. Mirrors live
/// `WorkspaceSnapshot` values into `@Observable` properties so SwiftUI and
/// the menubar can react.
@MainActor
@Observable
final class AppCoordinator {
    var snapshots: [WorkspaceSnapshot] = []
    var setupError: String?

    private let storage: WorkspaceStorage
    private var controllers: [UUID: WorkspaceController] = [:]
    private var pollTasks: [UUID: Task<Void, Never>] = [:]

    init(storage: WorkspaceStorage) {
        self.storage = storage
    }

    /// Load persisted workspaces and start their poll loops. Call once on
    /// app launch.
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

    /// Validate the API keys via fetchMe on both services, persist the
    /// workspace, store the keys in Keychain, and start the poll loop.
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

            applySnapshot(
                WorkspaceSnapshot(
                    workspaceId: workspace.id,
                    workspaceName: workspace.name,
                    runningIssueId: nil,
                    runningIssueIdentifier: nil,
                    runningIssueTitle: nil,
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
            snapshots[idx] = snapshot
        } else {
            snapshots.append(snapshot)
        }
    }
}
