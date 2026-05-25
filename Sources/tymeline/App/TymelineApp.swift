import SwiftUI

@main
struct TymelineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // SwiftUI's `App` protocol requires a Scene. The actual Settings UI
        // is presented by SettingsWindowController (an explicit NSWindow)
        // because the SwiftUI Settings scene does not reliably open in
        // LSUIElement=YES menubar apps. This Settings scene is just the
        // placeholder required by the protocol.
        Settings { EmptyView() }
    }
}
