import AppKit
import TymelineCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator: AppCoordinator
    let updater: UpdaterService
    let loginItem: LoginItemController
    private var menuBarController: MenuBarController?
    private var settingsWindowController: SettingsWindowController?

    override init() {
        let storage: WorkspaceStorage
        let secretStorage: SecretStorage
        do {
            storage = try WorkspaceStorage()
            secretStorage = try SecretStorage()
        } catch {
            fatalError("Could not initialise storage: \(error)")
        }
        self.coordinator = AppCoordinator(storage: storage, secretStorage: secretStorage)
        self.updater = UpdaterService()
        self.loginItem = LoginItemController()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settingsController = SettingsWindowController(coordinator: coordinator)
        self.settingsWindowController = settingsController

        menuBarController = MenuBarController(
            coordinator: coordinator,
            updater: updater,
            loginItem: loginItem,
            openSettings: { [weak settingsController] in
                settingsController?.showWindow()
            }
        )

        Task { @MainActor in
            await coordinator.bootstrap()
        }
    }
}
