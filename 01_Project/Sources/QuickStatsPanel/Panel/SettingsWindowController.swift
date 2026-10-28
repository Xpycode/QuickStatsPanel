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
final class SettingsWindowController: NSObject, NSToolbarDelegate {

    private var window: NSWindow?
    private let navigation = SettingsNavigation()

    func show(store: StatsStore) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(store: store, navigation: navigation))
            let window = NSWindow(contentViewController: hosting)
            window.title = "QuickStatsPanel — \(navigation.pane.title)"
            window.styleMask = [.titled, .closable, .resizable]
            let toolbar = NSToolbar(identifier: "QuickStatsPanel.Settings")
            toolbar.delegate = self
            toolbar.allowsUserCustomization = false
            toolbar.displayMode = .iconAndLabel
            toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(navigation.pane.rawValue)
            window.toolbar = toolbar
            window.toolbarStyle = .preference
            window.setContentSize(NSSize(width: 760, height: 520))
            window.contentMinSize = NSSize(width: 660, height: 440)
            window.isReleasedWhenClosed = false   // reuse across opens
            window.center()
            self.window = window
        }
        // Accessory apps must activate before a window can come forward + become
        // key. ignoringOtherApps so it reliably beats whatever was focused.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = SettingsPane(rawValue: identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = pane.title
        item.paletteLabel = pane.title
        item.image = NSImage(systemSymbolName: pane.systemImage, accessibilityDescription: pane.title)
        item.target = self
        item.action = #selector(selectPane(_:))
        return item
    }

    @objc private func selectPane(_ sender: NSToolbarItem) {
        guard let pane = SettingsPane(rawValue: sender.itemIdentifier.rawValue) else { return }
        navigation.pane = pane
        window?.title = "QuickStatsPanel — \(pane.title)"
    }
}
