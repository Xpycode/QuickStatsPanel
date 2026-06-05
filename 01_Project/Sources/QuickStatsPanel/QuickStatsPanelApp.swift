import SwiftUI

@main
struct QuickStatsPanelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Agent app with no standard windows. The real settings live in a
        // self-managed NSWindow (SettingsWindowController), opened from the panel's
        // gear — the SwiftUI `Settings` scene's `showSettingsWindow:` is unreliable
        // under LSUIElement (see SettingsWindowController). This empty scene just
        // satisfies the `some Scene` requirement.
        Settings { EmptyView() }
    }
}
