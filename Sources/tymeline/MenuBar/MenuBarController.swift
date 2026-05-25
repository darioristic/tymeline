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

        for snapshot in coordinator.snapshots where snapshot.runningIssueId == nil {
            let line = snapshot.lastErrorDescription != nil
                ? "\(snapshot.workspaceName): error"
                : "\(snapshot.workspaceName): idle"
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
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
}
