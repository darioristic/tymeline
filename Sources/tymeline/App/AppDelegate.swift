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
        // draw a blank/template-tinted icon. Load from the .icns file
        // directly (NSImage(named:) sometimes returns a template-flagged
        // copy from the asset catalog, which makes NC render it as a
        // white silhouette) and force isTemplate=false so the full colors
        // come through.
        let icon: NSImage? = {
            if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
               let img = NSImage(contentsOfFile: path) {
                return img
            }
            return NSImage(named: "AppIcon")
        }()
        if let icon {
            icon.isTemplate = false
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
