import AppKit
import SwiftUI

/// Owns a real, titled `NSWindow` that hosts `SettingsView`.
///
/// **Why not the SwiftUI `Settings` scene?** In an `LSUIElement` (accessory) app
/// the conventional `showSettingsWindow:` action is unreliable — with no regular
/// activation the responder chain often can't find the Settings scene, so the
/// action silently no-ops (the symptom: focus shifts but no window appears). We
/// already drive our own AppKit windows (the panel), so we manage this one too:
/// build it once, then `activate` + `makeKeyAndOrderFront`. Becoming **key** is
/// also what lets the in-panel hotkey recorder capture keystrokes.
@MainActor
final class SettingsWindowController {

    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "QuickStatsPanel Settings"
            // Resizable: the sidebar `NavigationSplitView` fills its window rather than
            // hugging content, so we give it an explicit default + min size (180pt
            // sidebar + 380pt detail floor) instead of letting it collapse.
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 600, height: 460))
            window.contentMinSize = NSSize(width: 560, height: 420)
            window.isReleasedWhenClosed = false   // reuse across opens
            window.center()
            self.window = window
        }
        // Accessory apps must activate before a window can come forward + become
        // key. ignoringOtherApps so it reliably beats whatever was focused.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
