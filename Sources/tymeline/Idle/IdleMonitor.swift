import AppKit
import CoreGraphics
import Foundation
import os

private let log = Logger(subsystem: "app.tymeline", category: "IdleMonitor")

/// Watches for screen lock, system sleep, and HID input idle so we can
/// nudge or stop the user's timer when they've clearly walked away.
///
/// Away state is `max(secondsSinceLock, secondsSinceInput)`:
///  - at warnThreshold we fire a banner ("still tracking?")
///  - at stopThreshold we auto-stop the timer
///
/// Both thresholds and callbacks are injected so the monitor stays free
/// of AppCoordinator details and is trivial to drive in a test.
@MainActor
final class IdleMonitor {
    var isAnyTimerRunning: @MainActor () -> Bool = { false }
    var onWarn: @MainActor (TimeInterval) -> Void = { _ in }
    var onAutoStop: @MainActor (TimeInterval) -> Void = { _ in }

    private let warnThreshold: TimeInterval
    private let stopThreshold: TimeInterval
    private let pollInterval: TimeInterval

    private var lockedAt: Date?
    private var warnedAt: Date?
    /// User tapped 'Still working' — snooze warns + auto-stop until this time.
    private var snoozeUntil: Date?
    private var pollTimer: Timer?

    init(
        warnThreshold: TimeInterval = 5 * 60,
        stopThreshold: TimeInterval = 10 * 60,
        pollInterval: TimeInterval = 30
    ) {
        self.warnThreshold = warnThreshold
        self.stopThreshold = stopThreshold
        self.pollInterval = pollInterval
    }

    /// Called when the user taps 'Yes, still working' on the warn banner.
    /// Snoozes any further warn / auto-stop for the next 30 min.
    func userConfirmedActive() {
        snoozeUntil = Date().addingTimeInterval(30 * 60)
        warnedAt = nil
        log.info("user confirmed active; snoozed for 30min")
    }

    func start() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.markLocked(reason: "willSleep")
            }
        }
        workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clearLocked(reason: "didWake")
            }
        }

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.markLocked(reason: "screenIsLocked")
            }
        }
        distributed.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clearLocked(reason: "screenIsUnlocked")
            }
        }

        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func markLocked(reason: String) {
        if lockedAt == nil {
            lockedAt = Date()
            log.info("away started: \(reason, privacy: .public)")
        }
        tick()
    }

    private func clearLocked(reason: String) {
        if lockedAt != nil {
            log.info("away ended: \(reason, privacy: .public)")
        }
        lockedAt = nil
        warnedAt = nil
    }

    private func tick() {
        guard isAnyTimerRunning() else {
            warnedAt = nil
            return
        }
        if let until = snoozeUntil, Date() < until {
            return
        }

        let lockedSeconds = lockedAt.map { Date().timeIntervalSince($0) } ?? 0
        let idleSeconds = systemIdleSeconds()
        let away = max(lockedSeconds, idleSeconds)

        if away >= stopThreshold {
            log.info("auto-stop triggered: away=\(Int(away), privacy: .public)s")
            onAutoStop(away)
            warnedAt = nil
        } else if away >= warnThreshold {
            if warnedAt == nil {
                log.info("warn triggered: away=\(Int(away), privacy: .public)s")
                onWarn(away)
                warnedAt = Date()
            }
        } else {
            warnedAt = nil
        }
    }

    /// Seconds since the last keyboard/mouse input. Uses combinedSessionState
    /// so it counts events across all event-tap locations.
    private func systemIdleSeconds() -> TimeInterval {
        let anyEventType = CGEventType(rawValue: ~0) ?? .null
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEventType)
    }
}
