import AppKit
import SwiftUI

/// `NSHostingView` subclass that accepts the first mouse click.
///
/// The strip lives in a non-activating panel, so without this the first click
/// after it appears would only raise the window and be swallowed before SwiftUI
/// saw it. (Same fix MousePlus's ring overlay uses.)
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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

    var isVisible: Bool { panel?.isVisible ?? false }

    /// The strip panel's on-screen frame, or `nil` when hidden. Used by the
    /// detail panel to anchor its card beneath the strip.
    var frame: NSRect? { panel?.frame }

    /// Toggle: hide if showing, otherwise show `content` at `anchor`.
    func toggle<Content: View>(anchor: PanelAnchor, @ViewBuilder content: () -> Content) {
        if isVisible { hide() } else { show(anchor: anchor, content: content()) }
    }

    func show<Content: View>(anchor: PanelAnchor, content: Content) {
        let hosting = FirstMouseHostingView(rootView: AnyView(content))

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

        let origin = origin(forSize: size, anchor: anchor)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        onVisibilityChanged?(true)
    }

    func hide() {
        // Guard so redundant hides (e.g. click-away after Esc already fired)
        // don't emit a second `false` and double-unregister downstream.
        guard panel != nil else { return }
        panel?.orderOut(nil)
        panel = nil
        hosting = nil
        onVisibilityChanged?(false)
    }

    // MARK: - Geometry

    private func origin(forSize size: NSSize, anchor: PanelAnchor) -> NSPoint {
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
        panel.isMovable = false
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
