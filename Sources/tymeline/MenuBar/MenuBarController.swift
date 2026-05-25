import AppKit
import Combine
import Observation
import TymelineCore

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let coordinator: AppCoordinator
    private var observationTask: Task<Void, Never>?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        rebuildMenu()
        startObserving()
    }

    deinit {
        observationTask?.cancel()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "tymeline")
        button.image?.isTemplate = true
        button.toolTip = "tymeline (idle)"
    }

    private func startObserving() {
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                _ = self.coordinator.snapshots
                _ = self.coordinator.setupError
                await MainActor.run {
                    self.refresh()
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func refresh() {
        if let running = coordinator.firstRunningSnapshot,
           let identifier = running.runningIssueIdentifier,
           let title = running.runningIssueTitle {
            statusItem.button?.image = NSImage(
                systemSymbolName: "clock.fill",
                accessibilityDescription: "tymeline running"
            )
            statusItem.button?.image?.isTemplate = true
            statusItem.button?.toolTip = "tymeline: \(identifier) \(title)"
        } else if coordinator.hasErrorSnapshot {
            statusItem.button?.image = NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: "tymeline error"
            )
            statusItem.button?.image?.isTemplate = true
            statusItem.button?.toolTip = "tymeline: error - see Settings"
        } else {
            statusItem.button?.image = NSImage(
                systemSymbolName: "clock",
                accessibilityDescription: "tymeline idle"
            )
            statusItem.button?.image?.isTemplate = true
            statusItem.button?.toolTip = "tymeline (idle)"
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let header: NSMenuItem
        if let running = coordinator.firstRunningSnapshot,
           let identifier = running.runningIssueIdentifier,
           let title = running.runningIssueTitle {
            header = NSMenuItem(
                title: "Running: \(identifier) \(title)",
                action: nil,
                keyEquivalent: ""
            )
        } else if coordinator.snapshots.isEmpty {
            header = NSMenuItem(title: "tymeline (no workspaces)", action: nil, keyEquivalent: "")
        } else {
            header = NSMenuItem(title: "tymeline (idle)", action: nil, keyEquivalent: "")
        }
        header.isEnabled = false
        menu.addItem(header)

        for snapshot in coordinator.snapshots where snapshot.runningIssueId == nil {
            let line: String
            if let err = snapshot.lastErrorDescription {
                line = "\(snapshot.workspaceName): error"
                _ = err
            } else {
                line = "\(snapshot.workspaceName): idle"
            }
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
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

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
