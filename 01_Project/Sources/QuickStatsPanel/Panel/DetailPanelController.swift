import AppKit
import SwiftUI

/// Shows a stat's detail card in a small borderless, non-activating `NSPanel`
/// beneath the strip. Replaces SwiftUI's native `.popover`, which drew system
/// chrome (a large "Tahoe" corner radius, translucent material, and an arrow)
/// that clashed with the strip's flat look. Here the app draws the card itself
/// (`StatDetailView`) with the strip's own `Theme`, so it belongs to the app.
///
/// Mirrors `PanelWindowController`'s panel setup (D-001): floating level,
/// non-activating so it never steals focus, content-driven size measured once per
/// open (no per-tick resize / jitter).
@MainActor
final class DetailPanelController {

    private var panel: NSPanel?
    private var hosting: NSHostingView<AnyView>?

    /// Which tile's detail is currently shown, or `nil` when hidden. Lets the
    /// strip toggle: tapping the open tile again hides; tapping another swaps.
    private(set) var openKind: StatKind?

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Gap between the strip's edge and the detail card.
    private let gap: CGFloat = 6

    /// Toggle the detail for `kind`. `stripFrame` is the strip panel's on-screen
    /// frame; `anchorX` is the screen-x to center the card under (the click point).
    func toggle<Content: View>(kind: StatKind,
                               stripFrame: NSRect,
                               anchorX: CGFloat,
                               @ViewBuilder content: () -> Content) {
        if openKind == kind {
            hide()
        } else {
            show(kind: kind, stripFrame: stripFrame, anchorX: anchorX, content: content())
        }
    }

    func show<Content: View>(kind: StatKind, stripFrame: NSRect, anchorX: CGFloat, content: Content) {
        let hosting = NSHostingView(rootView: AnyView(content))
        // Measure the card's ideal size once, now — it won't resize while open
        // even as values tick (same "measure once per summon" rule as the strip).
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = self.panel ?? makePanel(size: size)
        panel.contentView = hosting

        let origin = origin(forSize: size, stripFrame: stripFrame, anchorX: anchorX)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()

        self.hosting = hosting
        self.panel = panel
        self.openKind = kind
    }

    func hide() {
        guard panel != nil else { return }
        panel?.orderOut(nil)
        panel = nil
        hosting = nil
        openKind = nil
    }

    // MARK: - Geometry

    /// Center the card on `anchorX` and sit it just below the strip. If it would
    /// fall off the bottom of the screen, flip it above the strip instead; then
    /// clamp fully on-screen.
    private func origin(forSize size: NSSize, stripFrame: NSRect, anchorX: CGFloat) -> NSPoint {
        let host = NSScreen.screens.first {
            $0.frame.contains(NSPoint(x: stripFrame.midX, y: stripFrame.midY))
        } ?? NSScreen.main
        let visible = host?.visibleFrame ?? stripFrame

        var x = anchorX - size.width / 2
        var y = stripFrame.minY - gap - size.height          // below the strip
        if y < visible.minY { y = stripFrame.maxY + gap }    // no room → above it

        if visible.width >= size.width {
            x = min(max(x, visible.minX), visible.maxX - size.width)
        } else {
            x = visible.minX
        }
        if visible.height >= size.height {
            y = min(max(y, visible.minY), visible.maxY - size.height)
        }
        return NSPoint(x: x, y: y)
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
        panel.backgroundColor = .clear      // SwiftUI draws the rounded card
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.hasShadow = true              // window shadow hugs the rounded card
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true // no controls; never needs focus
        return panel
    }
}
