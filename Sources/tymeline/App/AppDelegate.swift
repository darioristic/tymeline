import AppKit
import TymelineCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator: AppCoordinator
    private var menuBarController: MenuBarController?
    private var settingsWindowController: SettingsWindowController?

    override init() {
        let storage: WorkspaceStorage
        do {
            storage = try WorkspaceStorage()
        } catch {
            fatalError("Could not initialise workspace storage: \(error)")
        }
        self.coordinator = AppCoordinator(storage: storage)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settingsController = SettingsWindowController(coordinator: coordinator)
        self.settingsWindowController = settingsController

        menuBarController = MenuBarController(
            coordinator: coordinator,
            openSettings: { [weak settingsController] in
                settingsController?.showWindow()
            }
        )

        Task { @MainActor in
            await coordinator.bootstrap()
        }
    }
}
