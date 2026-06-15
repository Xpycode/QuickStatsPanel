import AppKit

/// Wires the app together: starts sampling, registers the global hotkey, and
/// toggles the panel. No menu bar, no Dock icon (decision D-003) — the hotkey
/// and the panel itself are the entire UI surface.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let store = StatsStore()
    private let panel = PanelWindowController()
    /// The flat detail card shown beneath the strip when a tile is tapped. A
    /// separate borderless panel we draw ourselves, replacing the system popover
    /// so the card matches the strip's flat Theme (no arrow, small corner radius).
    private let detailPanel = DetailPanelController()
    /// One-time first-run hint card teaching the summon hotkey. Shown once beneath
    /// the strip on the very first launch (this Dock-less agent app has no other
    /// cue for how to bring the panel back). Tears down with the strip.
    private let hintPanel = HintPanelController()
    private let hotKey = HotKeyService(id: 1)
    private let settingsWindow = SettingsWindowController()

    /// Esc-to-dismiss. Registered as a bare-Escape Carbon hotkey *only while the
    /// panel is visible* (and torn down on hide), so Escape behaves normally for
    /// every other app the rest of the time. Carbon is permission-free and fires
    /// regardless of focus — the only such option for a non-activating panel that
    /// never becomes key. (id: 2 keeps it distinct from the toggle hotkey.)
    private let dismissHotKey = HotKeyService(id: 2)

    /// ⌘,-to-open-Settings. Registered only while the panel is visible (and torn
    /// down on hide), mirroring `dismissHotKey` — ⌘, is the macOS-standard
    /// Settings shortcut but there's no menu bar to host it, and the non-activating
    /// panel never becomes key, so a scoped Carbon hotkey is the only fit (D-010
    /// pattern). (id: 3 keeps it distinct from the toggle and dismiss hotkeys.)
    private let settingsHotKey = HotKeyService(id: 3)

    /// Toggle "Keep on Screen" (pin) from the keyboard. Registered only while the
    /// panel is visible (and torn down on hide), mirroring `dismissHotKey` —
    /// pinning is meaningless when nothing is shown. Rebindable in Settings; the
    /// binding is read at register time so a changed combo applies on next summon.
    /// (id: 4 keeps it distinct from the toggle/dismiss/settings hotkeys.)
    private let pinToggleHotKey = HotKeyService(id: 4)

    /// Global mouse monitor for click-away dismissal. A *mouse* monitor needs no
    /// special permission (unlike a keyboard one), keeping us permission-free.
    private var clickAwayMonitor: Any?

    /// "Pin" state (Keep on Screen). While pinned, click-away no longer dismisses
    /// the strip so it stays put for a longer read; Esc and the toggle hotkey still
    /// hide it (the deliberate "I'm done" gestures). Stored on `AppSettings.shared`
    /// (transient, not persisted) so the strip can observe it for its pinned
    /// indicator. Per-summon: reset whenever the strip hides (see below).
    private var isPinned: Bool {
        get { AppSettings.shared.isPinned }
        set { AppSettings.shared.isPinned = newValue }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        wireSettings()
        store.start()
        registerHotKey()
        installClickAwayMonitor()
        installEscToDismiss()
        installPanelInteractions()
        installMainMenu()

        // First-run discoverability: an agent app with no Dock/menu-bar presence
        // is invisible until summoned, so show the panel once on launch.
        togglePanel()
        showFirstRunHintIfNeeded()
    }

    /// On the very first launch, show a one-time hint card beneath the strip
    /// teaching the summon hotkey — the only way back in this Dock-less agent app.
    /// Policy (user choice): mark seen on first display so it never returns. The
    /// card tears down with the strip via `onVisibilityChanged` (see below), so it
    /// needs no dismissal logic of its own.
    private func showFirstRunHintIfNeeded() {
        let settings = AppSettings.shared
        guard !settings.hasSeenHint else { return }

        // Defer one beat before anchoring. The samplers deliver their first values
        // via async main-actor hops (e.g. battery presence decides whether that
        // tile shows), so the strip's content-driven width (D-008) is still
        // settling when this runs synchronously at end-of-launch. Reading
        // panel.frame now would center the card under the *half-built* strip,
        // leaving it visibly off to one side. A short delay lets the first samples
        // land and the strip reach its final width first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, let stripFrame = self.panel.frame else { return }
            self.hintPanel.show(stripFrame: stripFrame) {
                FirstRunHintView(hotKey: settings.hotKey.displayString)
            }
            settings.hasSeenHint = true
        }
    }

    /// Connect settings changes that need an *imperative* reaction. Declarative
    /// settings (anchor, strip height, stat set) are read where they're used and
    /// need no hook here.
    private func wireSettings() {
        let settings = AppSettings.shared
        settings.onHotKeyChanged = { [weak self] in self?.registerHotKey() }
        settings.onIntervalChanged = { [weak self] in self?.store.restart() }
    }

    /// (Re)register the global hotkey from the current setting.
    private func registerHotKey() {
        hotKey.register(AppSettings.shared.hotKey) { [weak self] in
            self?.togglePanel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        hotKey.unregister()
        dismissHotKey.unregister()
        settingsHotKey.unregister()
        pinToggleHotKey.unregister()
        removeClickAwayMonitor()
    }

    private func togglePanel() {
        // Width is content-driven (PanelWindowController measures the SwiftUI
        // content); anchor + height come from settings. A dragged custom position,
        // if any, wins over the anchor so the strip reappears where it was left.
        panel.toggle(anchor: AppSettings.shared.anchor,
                     customOrigin: AppSettings.shared.customPosition) { [store] in
            StatsStripView(
                store: store,
                onOpenSettings: { [weak self] in self?.openSettings() },
                onTileTap: { [weak self] kind in self?.toggleDetail(for: kind) }
            )
        }
    }

    /// Wire the strip's direct-manipulation affordances: the right-click menu and
    /// drag-to-reposition persistence. Set once at launch; `PanelWindowController`
    /// re-applies the menu provider to each freshly-built strip.
    private func installPanelInteractions() {
        panel.contextMenuProvider = { [weak self] in
            self?.makePanelMenu() ?? NSMenu()
        }
        // Persist a user drag so the strip re-summons at the spot it was left.
        panel.onPanelMoved = { origin in
            AppSettings.shared.customPosition = origin
        }
    }

    /// Toggle the flat detail card for `kind`, anchored beneath the strip and
    /// centered on the click. The card reads the store live (StatDetailView), so
    /// values keep ticking while it's open.
    private func toggleDetail(for kind: StatKind) {
        guard let stripFrame = panel.frame else { return }
        detailPanel.toggle(kind: kind,
                           stripFrame: stripFrame,
                           anchorX: NSEvent.mouseLocation.x) { [store] in
            StatDetailView(store: store, kind: kind)
        }
    }

    /// Open our settings window. Uses a self-managed `NSWindow` rather than the
    /// SwiftUI `Settings` scene, which is unreliable in an `LSUIElement` app.
    private func openSettings() {
        // The strip floats at `.floating` level, so it would sit *on top* of the
        // normal-level Settings window — pinning ("Keep on Screen") makes that
        // worse since it no longer dismisses on click-away. Settings is its own
        // full context, so close the strip as we open it. (hide() also resets pin
        // and tears down the detail/hint cards via onVisibilityChanged.)
        panel.hide()
        settingsWindow.show()
    }

    // MARK: - Esc-to-dismiss

    /// Capture Escape only while the panel is on screen. Driven by the panel's
    /// own visibility signal so it covers *every* hide path (toggle, click-away,
    /// Esc itself) — registering in `togglePanel()` alone would leave Escape
    /// captured after a click-away dismissal.
    private func installEscToDismiss() {
        panel.onVisibilityChanged = { [weak self] visible in
            guard let self else { return }
            // Run the costly top-processes sampler only while the panel is shown.
            self.store.setPanelVisible(visible)
            if visible {
                self.dismissHotKey.register(.escape) { [weak self] in
                    self?.panel.hide()
                }
                self.settingsHotKey.register(.commaSettings) { [weak self] in
                    self?.openSettings()
                }
                // Read the binding now so a rebind applies on the next summon.
                self.pinToggleHotKey.register(AppSettings.shared.pinHotKey) { [weak self] in
                    self?.isPinned.toggle()
                }
            } else {
                self.dismissHotKey.unregister()
                self.settingsHotKey.unregister()
                self.pinToggleHotKey.unregister()
                // Pinning is per-summon: any hide path (toggle, Esc, click-away)
                // clears it so the next summon is never unexpectedly stuck on.
                self.isPinned = false
                // The detail and hint cards are anchored to the strip — when the
                // strip goes (toggle, Esc, click-away), they go with it.
                self.detailPanel.hide()
                self.hintPanel.hide()
            }
        }
    }

    // MARK: - Click-away dismissal

    private func installClickAwayMonitor() {
        clickAwayMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            // A global monitor only fires for clicks in *other* apps, i.e. outside
            // our panel — exactly the click-away case. Hide if visible.
            Task { @MainActor in
                // A pinned strip ignores click-away — the user asked it to stay.
                guard let self, self.panel.isVisible, !self.isPinned else { return }
                self.panel.hide()
            }
        }
    }

    private func removeClickAwayMonitor() {
        if let clickAwayMonitor { NSEvent.removeMonitor(clickAwayMonitor) }
        clickAwayMonitor = nil
    }

    // MARK: - Application main menu

    /// Install a minimal application menu so standard key equivalents work whenever
    /// the app is *active* (a window is key). This is what gives ⌘, a real home: it
    /// opens Settings from anywhere the app is frontmost — complementing the strip-
    /// scoped Carbon ⌘, that covers the glance flow (strip up, app not activated).
    ///
    /// **Why this doesn't break the chrome-free identity:** the strip is a
    /// `.nonactivating` panel, so summoning it never activates the app — the menu
    /// bar stays hidden during a glance. It appears only when the Settings window is
    /// focused, which is exactly when a menu bar is appropriate. The menu also makes
    /// that window well-behaved: ⌘W to close, ⌘Q to quit, and cut/copy/paste for the
    /// color-picker fields (standard responder-chain selectors, target = first
    /// responder via `nil`).
    private func installMainMenu() {
        let mainMenu = NSMenu()

        // App menu — its title is auto-filled with the process name when the item
        // has an empty title and a submenu.
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu

        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit QuickStatsPanel",
                                  action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)

        // Edit menu — standard responder selectors so cut/copy/paste reach whatever
        // field (e.g. the color pickers) holds focus. The `copy(_:)` cast picks the
        // action overload over `NSObject.copy()` (otherwise ambiguous).
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",
                         action: #selector(NSText.copy(_:) as (NSText) -> (Any?) -> Void),
                         keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // Window menu — gives the Settings window ⌘W (close) and ⌘M (minimize),
        // routed to the key window through the responder chain.
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Right-click menu

    /// Build the strip's context menu fresh on each right-click so item state
    /// (the Pin checkmark, whether "Reset Position" is enabled) reflects the
    /// current moment. Rebuilt rather than cached for exactly that reason.
    private func makePanelMenu() -> NSMenu {
        let menu = NSMenu()

        let pin = NSMenuItem(title: "Keep on Screen",
                             action: #selector(togglePin), keyEquivalent: "")
        pin.target = self
        pin.state = isPinned ? .on : .off
        menu.addItem(pin)

        menu.addItem(.separator())

        let reset = NSMenuItem(title: "Reset Position",
                               action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        // Only meaningful once the strip has actually been dragged somewhere.
        reset.isEnabled = AppSettings.shared.customPosition != nil
        menu.addItem(reset)

        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit QuickStatsPanel",
                              action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func togglePin() {
        isPinned.toggle()
    }

    /// Clear the dragged position and snap the visible strip back to its anchor.
    @objc private func resetPosition() {
        AppSettings.shared.customPosition = nil
        panel.reposition(anchor: AppSettings.shared.anchor, customOrigin: nil)
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }
}
