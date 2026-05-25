import AppKit
import SwiftUI
import TymelineCore

/// Owns a single Settings NSWindow hosting the SwiftUI SettingsView.
///
/// Necessary because the standard SwiftUI `Settings` scene does not reliably
/// open in `LSUIElement=YES` (menubar-only) apps. Creating an NSWindow
/// directly and calling `makeKeyAndOrderFront` bypasses the broken default
/// behaviour while keeping the SwiftUI view code unchanged.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let coordinator: AppCoordinator

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func showWindow() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(coordinator: coordinator))
            let window = NSWindow(contentViewController: hosting)
            window.title = "tymeline Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 540, height: 420))
            window.minSize = NSSize(width: 520, height: 380)
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Keep the window object around for reuse - just lets it hide.
    }
}
