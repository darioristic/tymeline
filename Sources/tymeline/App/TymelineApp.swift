import SwiftUI

@main
struct TymelineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}
