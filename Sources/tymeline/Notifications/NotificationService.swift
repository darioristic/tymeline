import Foundation
@preconcurrency import UserNotifications
import os

private let log = Logger(subsystem: "app.tymeline", category: "Notifications")

private let idleCategoryId = "idle-warn"
private let actionStillActive = "still-active"
private let actionStopTimer = "stop-timer"

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var authorized: Bool = false

    /// Tapped 'Yes, still working' on the idle warn banner.
    var onStillActive: (() -> Void)?
    /// Tapped 'Stop timer' on the idle warn banner, or system-action stop.
    var onStopRequested: (() -> Void)?

    override init() {
        super.init()
        center.delegate = self
        registerIdleCategory()
    }

    /// Ask the user once for banner authorization. Idempotent - subsequent
    /// calls just refresh our cached `authorized` flag.
    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            authorized = granted
            log.info("notification authorization granted=\(granted, privacy: .public)")
        } catch {
            log.error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
            authorized = false
        }
    }

    func notifyStarted(identifier: String, title: String) {
        post(
            id: "start-\(identifier)-\(Date().timeIntervalSince1970)",
            title: "Started \(identifier)",
            body: title
        )
    }

    func notifyStopped(identifier: String, duration: TimeInterval) {
        post(
            id: "stop-\(identifier)-\(Date().timeIntervalSince1970)",
            title: "Stopped \(identifier)",
            body: durationString(duration)
        )
    }

    func notifyError(_ message: String) {
        post(
            id: "error-\(Date().timeIntervalSince1970)",
            title: "tymeline error",
            body: message
        )
    }

    /// Posts the interactive 'still working?' banner with two action buttons.
    /// Use the same notification id so a fresh warn replaces a stale one in
    /// Notification Center instead of stacking up.
    func notifyIdleWarn(identifier: String, idleMinutes: Int) {
        post(
            id: "idle-warn-\(identifier)",
            title: "Still working on \(identifier)?",
            body: "Idle for \(idleMinutes) min. Timer will auto-stop in 5 min.",
            categoryId: idleCategoryId
        )
    }

    private func registerIdleCategory() {
        let stillActive = UNNotificationAction(
            identifier: actionStillActive,
            title: "Yes, still working",
            options: []
        )
        let stopTimer = UNNotificationAction(
            identifier: actionStopTimer,
            title: "Stop timer",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: idleCategoryId,
            actions: [stillActive, stopTimer],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    private func post(id: String, title: String, body: String, categoryId: String? = nil) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let categoryId { content.categoryIdentifier = categoryId }

        // Attach the app icon as a thumbnail so it surfaces on the banner
        // even when macOS's iconservices cache hasn't picked up our bundle
        // icon (a known issue for fresh / ad-hoc-signed apps).
        if let iconURL = Self.bundledIconURL,
           let attachment = try? UNNotificationAttachment(identifier: "appicon", url: iconURL, options: nil) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        // Use the async API: the completion-handler form inherits @MainActor
        // isolation from this method under Swift 6 strict concurrency, then
        // UN dispatches the callback from a background queue and trips
        // libdispatch's main-thread assertion, crashing the app the moment
        // we post a "Started COO-XXX" notification.
        Task {
            do {
                try await center.add(request)
            } catch {
                log.error("notification post failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Lazily resolved URL to AppIcon.icns inside our bundle. Cached so
    /// every notification doesn't re-walk Bundle.main.
    private static let bundledIconURL: URL? = {
        guard let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns") else { return nil }
        return URL(fileURLWithPath: path)
    }()

    private func durationString(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banners even while the app is foreground (we're LSUIElement so
    /// there's no obvious foreground anyway, but be explicit).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionId = response.actionIdentifier
        Task { @MainActor [weak self] in
            switch actionId {
            case actionStillActive:
                self?.onStillActive?()
            case actionStopTimer:
                self?.onStopRequested?()
            default:
                break
            }
        }
        completionHandler()
    }
}
