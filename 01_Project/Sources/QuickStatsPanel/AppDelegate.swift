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

    /// Global mouse monitor for click-away dismissal. A *mouse* monitor needs no
    /// special permission (unlike a keyboard one), keeping us permission-free.
    private var clickAwayMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        wireSettings()
        store.start()
        registerHotKey()
        installClickAwayMonitor()
        installEscToDismiss()

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
        removeClickAwayMonitor()
    }

    private func togglePanel() {
        // Width is content-driven (PanelWindowController measures the SwiftUI
        // content); anchor + height come from settings.
        panel.toggle(anchor: AppSettings.shared.anchor) { [store] in
            StatsStripView(
                store: store,
                onOpenSettings: { [weak self] in self?.openSettings() },
                onTileTap: { [weak self] kind in self?.toggleDetail(for: kind) }
            )
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
            } else {
                self.dismissHotKey.unregister()
                self.settingsHotKey.unregister()
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
                guard let self, self.panel.isVisible else { return }
                self.panel.hide()
            }
        }
    }

    private func removeClickAwayMonitor() {
        if let clickAwayMonitor { NSEvent.removeMonitor(clickAwayMonitor) }
        clickAwayMonitor = nil
    }
}
