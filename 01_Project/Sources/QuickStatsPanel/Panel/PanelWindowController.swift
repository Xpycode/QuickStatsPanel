import AppKit
import SwiftUI

/// `NSHostingView` subclass that accepts the first mouse click.
///
/// The strip lives in a non-activating panel, so without this the first click
/// after it appears would only raise the window and be swallowed before SwiftUI
/// saw it. (Same fix MousePlus's ring overlay uses.)
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    /// Supplies the right-click menu for the strip. Set by `PanelWindowController`
    /// in `show`; `nil` falls back to the default (no menu).
    var contextMenuProvider: (() -> NSMenu)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Right-click anywhere on the strip pops the panel's context menu (Pin /
    /// Reset Position / Settings / Quit). This is local to our window, so it never
    /// reaches the *global* click-away monitor — the strip stays put while the menu
    /// is open. SwiftUI's `.contextMenu` is unreliable on a non-key, non-activating
    /// panel, so we drive `NSMenu` directly.
    override func rightMouseDown(with event: NSEvent) {
        if let menu = contextMenuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

/// Shows / hides the stats strip in a borderless, non-activating `NSPanel`.
/// Adapted from MousePlus `RingWindowController` (decision D-001).
@MainActor
final class PanelWindowController {

    /// Margin from the screen edge for the fixed top/bottom anchors.
    private let edgeMargin: CGFloat = 24

    private var panel: NSPanel?
    private var hosting: FirstMouseHostingView<AnyView>?

    /// Fired with `true` when the strip appears and `false` when it hides — via
    /// *any* route (toggle, click-away, Esc). Lets the owner scope behavior such
    /// as Esc-to-dismiss to exactly the window where the panel is on screen.
    var onVisibilityChanged: ((Bool) -> Void)?

    /// Fired with the strip's new bottom-left origin when the *user* drags it
    /// (programmatic moves are filtered out). The owner persists this as the
    /// custom summon position.
    var onPanelMoved: ((NSPoint) -> Void)?

    /// Supplies the right-click context menu. Set by the owner before the first
    /// `show`; applied to the hosting view each summon.
    var contextMenuProvider: (() -> NSMenu)?

    var isVisible: Bool { panel?.isVisible ?? false }

    /// The last origin we set *programmatically* (summon / reposition). Used to
    /// tell our own `setFrame` echoes apart from genuine user drags in the move
    /// observer — an exact match means we moved it, anything else is the user.
    private var lastAppliedOrigin: NSPoint?

    /// Guards the native AppKit drag loop. SwiftUI only detects that a drag has
    /// crossed its small threshold; AppKit then owns cursor tracking until mouse-up.
    private var nativeDragActive = false

    /// Token for the window-move observer, removed on hide.
    private var moveObserver: NSObjectProtocol?

    /// The strip panel's on-screen frame, or `nil` when hidden. Used by the
    /// detail panel to anchor its card beneath the strip.
    var frame: NSRect? { panel?.frame }

    /// Toggle: hide if showing, otherwise show `content` at `customOrigin` (a
    /// dragged spot) if present, else at `anchor`.
    func toggle<Content: View>(anchor: PanelAnchor,
                               customOrigin: NSPoint?,
                               @ViewBuilder content: () -> Content) {
        if isVisible { hide() }
        else { show(anchor: anchor, customOrigin: customOrigin, content: content()) }
    }

    func show<Content: View>(anchor: PanelAnchor, customOrigin: NSPoint?, content: Content) {
        let hosting = FirstMouseHostingView(rootView: AnyView(content))
        hosting.contextMenuProvider = contextMenuProvider

        // Content-driven size: ask the SwiftUI tree for its ideal size so the
        // strip hugs its tiles (and grows as tiles are added) rather than using a
        // fixed width. The content pins its own height, so this yields
        // (naturalContentWidth, stripHeight). Measured once per summon — the strip
        // won't resize while visible, avoiding jitter as readouts change digits.
        let size = hosting.fittingSize

        let panel = makePanel(size: size)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        self.hosting = hosting
        self.panel = panel

        let origin = origin(forSize: size, anchor: anchor, customOrigin: customOrigin)
        lastAppliedOrigin = origin
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        installMoveObserver(for: panel)
        panel.orderFrontRegardless()
        onVisibilityChanged?(true)
    }

    func hide() {
        // Guard so redundant hides (e.g. click-away after Esc already fired)
        // don't emit a second `false` and double-unregister downstream.
        guard panel != nil else { return }
        removeMoveObserver()
        panel?.orderOut(nil)
        panel = nil
        hosting = nil
        lastAppliedOrigin = nil
        nativeDragActive = false
        onVisibilityChanged?(false)
    }

    /// Reposition the *visible* strip to `customOrigin` (if given) or `anchor`,
    /// keeping its current size. Used by "Reset Position" to snap a dragged strip
    /// back to the configured anchor without rebuilding its content.
    func reposition(anchor: PanelAnchor, customOrigin: NSPoint?) {
        guard let panel else { return }
        let size = panel.frame.size
        let origin = origin(forSize: size, anchor: anchor, customOrigin: customOrigin)
        lastAppliedOrigin = origin
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Hand a strip-wide SwiftUI drag to AppKit's native window-drag loop. Updating
    /// `setFrameOrigin` from every SwiftUI gesture callback lags behind the pointer
    /// because those callbacks are paced by view rendering. `performDrag` tracks at
    /// the window server's cadence and returns only after mouse-up.
    func drag(translation: CGSize, ended: Bool) {
        if ended {
            nativeDragActive = false
            return
        }
        guard !nativeDragActive, let panel, let current = NSApp.currentEvent else { return }
        nativeDragActive = true

        // `performDrag` expects the initiating left-mouse-down event. SwiftUI calls
        // us on the first dragged event, so synthesize an equivalent mouse-down at
        // that exact window location, then let AppKit consume the remaining stream.
        guard let mouseDown = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: current.locationInWindow,
            modifierFlags: current.modifierFlags,
            timestamp: current.timestamp,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: current.eventNumber,
            clickCount: 1,
            pressure: current.pressure
        ) else {
            nativeDragActive = false
            return
        }
        panel.performDrag(with: mouseDown)
        let origin = panel.frame.origin
        lastAppliedOrigin = origin
        onPanelMoved?(origin)
    }

    // MARK: - Drag tracking

    /// Watch for window moves so user drags can be persisted as the custom
    /// position. Block-based observer wrapped in `MainActor.assumeIsolated` (same
    /// pattern as `AppSettings`'s accessibility observer) so it stays clean under
    /// `complete` strict concurrency without an `NSWindowDelegate` conformance.
    private func installMoveObserver(for panel: NSPanel) {
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                guard !self.nativeDragActive else { return }
                let origin = panel.frame.origin
                // Ignore our own `setFrame` echoes; only report genuine user drags.
                if origin == self.lastAppliedOrigin { return }
                self.lastAppliedOrigin = origin
                self.onPanelMoved?(origin)
            }
        }
    }

    private func removeMoveObserver() {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
    }

    // MARK: - Geometry

    private func origin(forSize size: NSSize, anchor: PanelAnchor,
                        customOrigin: NSPoint?) -> NSPoint {
        // A dragged position wins over the anchor — but *not* in cursor mode, whose
        // whole contract is "appear at the pointer, every summon." Letting a saved
        // drag override there made "At cursor" stop following the cursor the moment
        // the strip was nudged (even accidentally, by a click on its draggable
        // background). Cursor mode always recomputes from the live pointer below.
        // Clamp a saved spot to the screen it sits on so it stays valid if displays
        // change (a now-missing screen falls back to main via `screen(containing:)`).
        if anchor != .cursor, let custom = customOrigin {
            return clamp(origin: custom, size: size, on: screen(containing: custom))
        }

        // All anchors resolve relative to the screen the pointer is on, so the
        // strip lands on the active display in a multi-monitor setup.
        let cursor = NSEvent.mouseLocation       // global, bottom-left origin
        let host = screen(containing: cursor)

        switch anchor {
        case .cursor:
            // Center horizontally on the cursor; sit just below it so the strip
            // doesn't cover what's under the pointer.
            let gap: CGFloat = 18
            let raw = NSPoint(x: cursor.x - size.width / 2,
                              y: cursor.y - size.height - gap)
            return clamp(origin: raw, size: size, on: host)

        case .screenCenter, .topCenter, .bottomCenter:
            let raw = fixedOrigin(for: anchor, size: size,
                                  in: host?.visibleFrame ?? .zero)
            return clamp(origin: raw, size: size, on: host)
        }
    }

    /// Bottom-left origin for the fixed (non-cursor) anchors, in screen coords
    /// (y grows upward). `visible` is the host screen's `visibleFrame` (already
    /// excludes the menu bar / Dock). The result is clamped by the caller.
    private func fixedOrigin(for anchor: PanelAnchor,
                             size: NSSize,
                             in visible: NSRect) -> NSPoint {
        let centeredX = visible.midX - size.width / 2
        switch anchor {
        case .screenCenter:
            return NSPoint(x: centeredX, y: visible.midY - size.height / 2)
        case .topCenter:
            return NSPoint(x: centeredX, y: visible.maxY - size.height - edgeMargin)
        case .bottomCenter:
            return NSPoint(x: centeredX, y: visible.minY + edgeMargin)
        case .cursor:
            return visible.origin   // unreachable; handled above
        }
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    /// Keep the strip fully within the screen's visible frame.
    private func clamp(origin: NSPoint, size: NSSize, on screen: NSScreen?) -> NSPoint {
        guard let visible = screen?.visibleFrame else { return origin }
        var o = origin
        if visible.width >= size.width {
            o.x = min(max(o.x, visible.minX), visible.maxX - size.width)
        } else {
            o.x = visible.minX
        }
        if visible.height >= size.height {
            o.y = min(max(o.y, visible.minY), visible.maxY - size.height)
        } else {
            o.y = visible.minY
        }
        return o
    }

    // MARK: - Panel

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear      // SwiftUI draws the rounded background
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Let the user drag the strip by any empty region of its background. Tiles
        // and the gear are SwiftUI controls — they consume their own mouse-downs —
        // so only the gaps/padding initiate a window drag, and a plain tap never
        // moves it. The dragged spot is captured via the move observer (above).
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true

        // Float over other apps without stealing focus; still deliver mouse-moved
        // events so future hover affordances work.
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        return panel
    }
}
