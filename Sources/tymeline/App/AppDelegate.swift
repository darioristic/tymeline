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
        // LSUIElement apps don't get the dock-icon path that normally
        // primes NSApp.applicationIconImage, so notification banners
        // sometimes draw a blank/generic icon. Set it explicitly from
        // the asset catalog so UN has a concrete NSImage to render.
        if let icon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = icon
        }

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
