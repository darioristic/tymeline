import AppKit
import TymelineCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator: AppCoordinator
    private var menuBarController: MenuBarController?

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
        menuBarController = MenuBarController(coordinator: coordinator)

        Task { @MainActor in
            await coordinator.bootstrap()
        }
    }
}
