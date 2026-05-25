import AppKit
import TymelineCore

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let coordinator: AppCoordinator
    private let updater: UpdaterService
    private let openSettings: () -> Void
    private var tickTimer: Timer?

    init(coordinator: AppCoordinator, updater: UpdaterService, openSettings: @escaping () -> Void) {
        self.coordinator = coordinator
        self.updater = updater
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
        button.imagePosition = .imageLeading
        button.toolTip = "tymeline (idle)"
    }

    private func refresh() {
        updateButton()
        rebuildMenu()
        updateTickTimer()
    }

    /// Refreshes only the menubar button (icon + title). Cheap: safe to call
    /// every second from the tick timer without rebuilding the dropdown menu.
    private func updateButton() {
        guard let button = statusItem.button else { return }

        if let running = coordinator.firstRunningSnapshot,
           let identifier = running.runningIssueIdentifier,
           let title = running.runningIssueTitle {
            button.image = NSImage(systemSymbolName: "clock.badge.checkmark", accessibilityDescription: "tymeline running")
            button.image?.isTemplate = true
            let elapsed = elapsedString(since: running.runningStartedAt)
            button.title = elapsed.map { " \(identifier) \($0)" } ?? " \(identifier)"
            button.toolTip = "tymeline: \(identifier) \(title)"
        } else if coordinator.hasErrorSnapshot {
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "tymeline error")
            button.image?.isTemplate = true
            button.title = ""
            button.toolTip = "tymeline: error - see Settings"
        } else {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "tymeline idle")
            button.image?.isTemplate = true
            button.title = ""
            button.toolTip = "tymeline (idle)"
        }
    }

    private func updateTickTimer() {
        let shouldTick = coordinator.firstRunningSnapshot?.runningStartedAt != nil
        if shouldTick, tickTimer == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.updateButton()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            tickTimer = timer
        } else if !shouldTick, let timer = tickTimer {
            timer.invalidate()
            tickTimer = nil
        }
    }

    private func elapsedString(since start: Date?) -> String? {
        guard let start else { return nil }
        let seconds = max(0, Int(Date().timeIntervalSince(start)))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
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
                appendGroupedIssueItems(to: menu, snapshot: snapshot)
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

        let updateItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdatesAction),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateItem.isEnabled = updater.canCheckForUpdates
        menu.addItem(updateItem)

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        if let latest = coordinator.snapshots.compactMap(\.lastPollAt).max() {
            let syncItem = NSMenuItem(
                title: "Synced \(lastSyncString(latest))",
                action: nil,
                keyEquivalent: ""
            )
            syncItem.isEnabled = false
            menu.addItem(syncItem)
        }

        let quitItem = NSMenuItem(
            title: "Quit tymeline",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func appendGroupedIssueItems(to menu: NSMenu, snapshot: WorkspaceSnapshot) {
        let workspaceId = snapshot.workspaceId
        let issuesById = Dictionary(uniqueKeysWithValues: snapshot.assignedIssues.map { ($0.id, $0) })
        let childrenByParent = Dictionary(
            grouping: snapshot.assignedIssues.filter { $0.parentId != nil },
            by: { $0.parentId! }
        )

        // Top-level: an issue with no parent, OR a parent not in the assigned list.
        let topLevel = snapshot.assignedIssues.filter { issue in
            guard let parentId = issue.parentId else { return true }
            return issuesById[parentId] == nil
        }

        for issue in topLevel {
            let children = childrenByParent[issue.id] ?? []
            if children.isEmpty {
                menu.addItem(makeIssueItem(issue, workspaceId: workspaceId, snapshot: snapshot))
            } else {
                menu.addItem(
                    makeParentItem(
                        issue,
                        children: children,
                        workspaceId: workspaceId,
                        snapshot: snapshot
                    )
                )
            }
        }
    }

    private func makeIssueItem(
        _ issue: LinearIssue,
        workspaceId: UUID,
        snapshot: WorkspaceSnapshot
    ) -> NSMenuItem {
        let isRunning = snapshot.runningIssueId == issue.id
        let title = "\(issue.identifier) — \(issue.title)"
        let item = NSMenuItem(
            title: title,
            action: #selector(handleIssueClick(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = IssueClickContext(workspaceId: workspaceId, issue: issue)
        item.image = stateIcon(stateType: issue.stateType, isRunning: isRunning)
        if isRunning { item.state = .on }
        return item
    }

    private func makeParentItem(
        _ parent: LinearIssue,
        children: [LinearIssue],
        workspaceId: UUID,
        snapshot: WorkspaceSnapshot
    ) -> NSMenuItem {
        let runningId = snapshot.runningIssueId
        let parentRunning = runningId == parent.id
        let anyChildRunning = children.contains { $0.id == runningId }
        let title = "\(parent.identifier) — \(parent.title)"

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = stateIcon(
            stateType: parent.stateType,
            isRunning: parentRunning || anyChildRunning
        )
        if parentRunning || anyChildRunning { item.state = .mixed }

        let submenu = NSMenu()

        let parentLine = NSMenuItem(
            title: "Start \(parent.identifier) (parent)",
            action: #selector(handleIssueClick(_:)),
            keyEquivalent: ""
        )
        parentLine.target = self
        parentLine.representedObject = IssueClickContext(workspaceId: workspaceId, issue: parent)
        parentLine.image = stateIcon(stateType: parent.stateType, isRunning: parentRunning)
        if parentRunning { parentLine.state = .on }
        submenu.addItem(parentLine)

        submenu.addItem(NSMenuItem.separator())

        for child in children {
            submenu.addItem(makeIssueItem(child, workspaceId: workspaceId, snapshot: snapshot))
        }

        item.submenu = submenu
        return item
    }

    private func stateIcon(stateType: LinearIssueStateType, isRunning: Bool) -> NSImage? {
        let symbolName: String
        let color: NSColor

        if isRunning {
            symbolName = "play.circle.fill"
            color = .systemGreen
        } else if stateType == .started {
            symbolName = "play.circle.fill"
            color = .systemBlue
        } else {
            symbolName = "circle"
            color = .tertiaryLabelColor
        }

        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return nil
        }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return image.withSymbolConfiguration(config)
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    @objc private func checkForUpdatesAction() {
        updater.checkForUpdates()
    }

    private func lastSyncString(_ date: Date?) -> String {
        guard let date else { return "never" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 {
            let m = seconds / 60
            return "\(m)m ago"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
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
