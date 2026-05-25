import AppKit
import Sparkle

/// Thin wrapper around Sparkle's standard updater so the rest of the app
/// doesn't import Sparkle directly. Created once at launch; checks for
/// updates automatically in the background on the schedule configured by
/// Info.plist's SUEnableAutomaticChecks key.
@MainActor
final class UpdaterService {
    private let controller: SPUStandardUpdaterController

    init() {
        // startingUpdater: true wires up the background-check timer using
        // SUEnableAutomaticChecks / SUScheduledCheckInterval from Info.plist.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Triggers the manual "Check for Updates..." sheet — same as the user
    /// picking it from the menu. Shows "you're up to date" if there's nothing,
    /// otherwise the install prompt.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }
}
