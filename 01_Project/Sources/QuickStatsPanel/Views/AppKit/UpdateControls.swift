import AppKit
import SwiftUI

/// Native update button. Its enabled state follows Sparkle's active session.
struct CheckForUpdatesButton: NSViewRepresentable {
    @ObservedObject var updater: UpdaterController

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "Check for Updates…", target: updater,
                              action: #selector(UpdaterController.checkForUpdates(_:)))
        button.bezelStyle = .rounded
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.target = updater
        button.isEnabled = updater.isStarted && updater.canCheckForUpdates
    }
}
