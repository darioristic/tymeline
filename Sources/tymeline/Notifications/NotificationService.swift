import Foundation
import UserNotifications
import os

private let log = Logger(subsystem: "app.tymeline", category: "Notifications")

@MainActor
final class NotificationService {
    private let center = UNUserNotificationCenter.current()
    private var authorized: Bool = false

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

    private func post(id: String, title: String, body: String) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                log.error("notification post failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}
