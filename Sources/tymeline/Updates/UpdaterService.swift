import AppKit
import Sparkle

/// Thin wrapper around Sparkle's standard updater so the rest of the app
/// doesn't import Sparkle directly. Created once at launch; checks for
/// updates automatically in the background on the schedule configured by
/// Info.plist's SUEnableAutomaticChecks key.
///
/// Doubles as the Sparkle delegate so the menubar can paint a red dot on
/// the clock icon when an update is found - matches the rauchg/typing-stats
/// "update available" affordance.
@MainActor
final class UpdaterService: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!

    /// Non-nil while Sparkle knows about a newer version than the one running.
    /// Reset to nil if the next check finds nothing.
    private(set) var availableUpdateVersion: String?

    /// Fires whenever availableUpdateVersion changes, so callers (the menubar
    /// controller) can repaint the icon without having to poll.
    var onAvailabilityChange: (@MainActor () -> Void)?

    override init() {
        super.init()
        // startingUpdater: true wires up the background-check timer using
        // SUEnableAutomaticChecks / SUScheduledCheckInterval from Info.plist.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    /// Triggers the manual "Check for Updates..." sheet - same as the user
    /// picking it from the menu. Shows "you're up to date" if there's nothing,
    /// otherwise the install prompt.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor [weak self] in
            self?.availableUpdateVersion = version
            self?.onAvailabilityChange?()
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Task { @MainActor [weak self] in
            self?.availableUpdateVersion = nil
            self?.onAvailabilityChange?()
        }
    }
}
