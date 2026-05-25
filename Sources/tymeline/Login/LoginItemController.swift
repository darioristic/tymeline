import Foundation
import ServiceManagement
import os

private let log = Logger(subsystem: "app.tymeline", category: "LoginItem")

/// Thin wrapper around SMAppService so the menubar can read/write the
/// "start at login" flag without poking at the system framework directly.
/// macOS 13+ replaces the old SMLoginItemSetEnabled API with this — the
/// app registers itself and macOS handles the auto-launch.
@MainActor
final class LoginItemController {
    /// Returns true if the OS will launch tymeline on login.
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Flips the auto-launch flag. No-op if the requested state already
    /// matches what the OS reports. Swallows + logs errors instead of
    /// throwing - the menu item just won't change visibly.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                    log.info("registered for login launch")
                }
            } else {
                if SMAppService.mainApp.status != .notRegistered {
                    try SMAppService.mainApp.unregister()
                    log.info("unregistered from login launch")
                }
            }
        } catch {
            log.error("toggle login item failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
