import AppKit
import Sparkle
import os

private let log = Logger(subsystem: "app.tymeline", category: "Updater")

/// Thin wrapper around Sparkle's standard updater so the rest of the app
/// doesn't import Sparkle directly. Created once at launch; checks for
/// updates automatically in the background on the schedule configured by
/// Info.plist's SUEnableAutomaticChecks key.
///
/// Doubles as both the Sparkle updater delegate AND the standard user
/// driver delegate. The latter is required because tymeline is LSUIElement
/// (background-only) - without it, Sparkle suppresses scheduled-check
/// alerts so the user never sees that an update is available. Implementing
/// the "gentle reminder" hooks lets us paint the red dot ourselves and
/// only surface Sparkle's modal when the user explicitly clicks the menu.
@MainActor
final class UpdaterService: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
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
            userDriverDelegate: self
        )
        // Sparkle's first scheduled check is delayed by a random fraction
        // of SUScheduledCheckInterval, which can mean hours before the
        // user notices a fresh release. Kick off one immediate background
        // check ~10s after launch (gives the network stack and Sparkle
        // time to settle), then let the regular interval take over.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self else { return }
            log.info("kicking off initial background update check")
            self.controller.updater.checkForUpdatesInBackground()
        }
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
        log.info("didFindValidUpdate: \(version, privacy: .public)")
        Task { @MainActor [weak self] in
            self?.availableUpdateVersion = version
            self?.onAvailabilityChange?()
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        log.info("updaterDidNotFindUpdate: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor [weak self] in
            self?.availableUpdateVersion = nil
            self?.onAvailabilityChange?()
        }
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// Tells Sparkle that yes, we want gentle scheduled-update reminders
    /// (we draw the menubar badge instead of relying on a stolen-focus
    /// modal). Without returning true here, the warning in Sparkle's log
    /// becomes literal behavior: alerts never appear.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// When Sparkle would normally show a modal alert because of a
    /// scheduled check, defer to us. We surface the red dot + 'Install
    /// update' menu item; if the user clicks them we call checkForUpdates()
    /// which then drops them into the standard install flow.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        log.info("shouldHandleShowingScheduledUpdate version=\(update.displayVersionString, privacy: .public) immediateFocus=\(immediateFocus, privacy: .public)")
        // immediateFocus == true means the app is foreground and Sparkle
        // can safely show its modal. For a menubar app this is rare, so
        // let Sparkle handle that path; everything else we handle.
        return immediateFocus
    }

    /// Called when Sparkle is about to surface a scheduled update (either
    /// via us if we returned false above, or directly if we returned true).
    /// Either way, update the badge state so the menubar reflects it.
    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        log.info("willHandleShowingUpdate version=\(version, privacy: .public) handleShowing=\(handleShowingUpdate, privacy: .public)")
        Task { @MainActor [weak self] in
            self?.availableUpdateVersion = version
            self?.onAvailabilityChange?()
        }
    }
}
