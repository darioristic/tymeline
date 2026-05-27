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
        // Launch as a regular app so macOS registers our bundle (including
        // its icon) with NotificationCenter / Dock / iconservicesd the
        // normal way, then immediately hide the Dock tile via .accessory.
        // The Dock icon flashes for a tiny moment but the trade-off is
        // that NC now actually knows what our app icon looks like - which
        // LSUIElement=YES blocks because macOS short-circuits the
        // registration path for menu-bar-only bundles.
        NSApp.setActivationPolicy(.accessory)

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
            // Force-write the icon onto the bundle itself so NotificationCenter
            // resolves it via its standard lookup path. NSWorkspace.setIcon
            // bypasses iconservicesd's stale cache for ad-hoc-signed bundles
            // by writing the icon directly into the bundle as a "custom icon".
            NSWorkspace.shared.setIcon(icon, forFile: Bundle.main.bundlePath, options: [])
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
