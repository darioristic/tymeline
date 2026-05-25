import AppKit
import TymelineCore

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let coordinator: AppCoordinator
    private let openSettings: () -> Void

    init(coordinator: AppCoordinator, openSettings: @escaping () -> Void) {
        self.coordinator = coordinator
        self.openSettings = openSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        rebuildMenu()
        coordinator.onStateChange = { [weak self] in
            self?.refresh()
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "tymeline")
        button.image?.isTemplate = true
        button.toolTip = "tymeline (idle)"
    }

    private func refresh() {
        guard let button = statusItem.button else { return }

        if let running = coordinator.firstRunningSnapshot,
           let identifier = running.runningIssueIdentifier,
           let title = running.runningIssueTitle {
            button.image = NSImage(systemSymbolName: "clock.badge.checkmark", accessibilityDescription: "tymeline running")
            button.image?.isTemplate = true
            button.toolTip = "tymeline: \(identifier) \(title)"
        } else if coordinator.hasErrorSnapshot {
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "tymeline error")
            button.image?.isTemplate = true
            button.toolTip = "tymeline: error - see Settings"
        } else {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "tymeline idle")
            button.image?.isTemplate = true
            button.toolTip = "tymeline (idle)"
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // Header
        let headerTitle: String
        if let running = coordinator.firstRunningSnapshot,
           let identifier = running.runningIssueIdentifier,
           let title = running.runningIssueTitle {
            headerTitle = "Running: \(identifier) \(title)"
        } else if coordinator.snapshots.isEmpty {
            headerTitle = "tymeline (no workspaces)"
        } else {
            headerTitle = "tymeline (idle)"
        }
        let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        // Stop button if anything is running
        if coordinator.firstRunningSnapshot != nil {
            for snapshot in coordinator.snapshots where snapshot.runningIssueId != nil {
                let stopItem = NSMenuItem(
                    title: "Stop timer (\(snapshot.workspaceName))",
                    action: #selector(handleStopClick(_:)),
                    keyEquivalent: ""
                )
                stopItem.target = self
                stopItem.representedObject = WorkspaceRef(id: snapshot.workspaceId)
                menu.addItem(stopItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Per-workspace issue picker
        for snapshot in coordinator.snapshots {
            let workspaceHeader = NSMenuItem(title: snapshot.workspaceName, action: nil, keyEquivalent: "")
            workspaceHeader.isEnabled = false
            menu.addItem(workspaceHeader)

            if let err = snapshot.lastErrorDescription {
                let errItem = NSMenuItem(title: "  ⚠ \(err)", action: nil, keyEquivalent: "")
                errItem.isEnabled = false
                menu.addItem(errItem)
            }

            if snapshot.assignedIssues.isEmpty {
                let empty = NSMenuItem(
                    title: snapshot.lastPollAt == nil ? "  (loading...)" : "  (no assigned issues)",
                    action: nil,
                    keyEquivalent: ""
                )
                empty.isEnabled = false
                menu.addItem(empty)
            } else {
                for issue in snapshot.assignedIssues {
                    let badge = issue.stateType == .started ? "▶" : "·"
                    let title = "  \(badge) \(issue.identifier) — \(issue.title)"
                    let item = NSMenuItem(
                        title: title,
                        action: #selector(handleIssueClick(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = IssueClickContext(
                        workspaceId: snapshot.workspaceId,
                        issue: issue
                    )
                    if snapshot.runningIssueId == issue.id {
                        item.state = .on
                    }
                    menu.addItem(item)
                }
            }
        }

        // Action error
        if let actionError = coordinator.actionError {
            menu.addItem(NSMenuItem.separator())
            let errItem = NSMenuItem(title: "Error: \(actionError)", action: nil, keyEquivalent: "")
            errItem.isEnabled = false
            menu.addItem(errItem)
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit tymeline",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    @objc private func handleIssueClick(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? IssueClickContext else { return }
        let workspaceId = context.workspaceId
        let issue = context.issue
        Task { @MainActor in
            await coordinator.startTimer(workspaceId: workspaceId, issue: issue)
        }
    }

    @objc private func handleStopClick(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? WorkspaceRef else { return }
        let workspaceId = ref.id
        Task { @MainActor in
            await coordinator.stopRunningTimer(workspaceId: workspaceId)
        }
    }
}

/// Reference holder for NSMenuItem.representedObject (which needs `Any?`).
private final class IssueClickContext {
    let workspaceId: UUID
    let issue: LinearIssue
    init(workspaceId: UUID, issue: LinearIssue) {
        self.workspaceId = workspaceId
        self.issue = issue
    }
}

private final class WorkspaceRef {
    let id: UUID
    init(id: UUID) { self.id = id }
}
