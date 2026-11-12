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
        panel.acceptsMouseMovedEvents = false

        let origin = origin(forSize: size, stripFrame: stripFrame, anchorX: anchorX)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()

        self.hosting = hosting
        self.panel = panel
        self.openKind = kind
    }

    /// Reserved-frame positioning for presentations whose parent target must stay fixed
    /// (Ring). Supplements `show(kind:stripFrame:anchorX:content:)`; the strip path is
    /// untouched. `parentFrame` is the wedge's screen frame and `footprint` the
    /// presenting panel's frame; the card is placed outside the footprint, so it can
    /// never cover the parent target.
    func showBeside<Content: View>(kind: StatKind, parentFrame: NSRect, footprint: NSRect, content: Content) {
        let hosting = NSHostingView(rootView: AnyView(content))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = self.panel ?? makePanel(size: size)
        panel.contentView = hosting
        // The pointer route between presenting panel and card is observed by the owner;
        // the card must report moves for the part of that route that crosses it.
        panel.acceptsMouseMovedEvents = true

        let host = NSScreen.screens.first {
            $0.frame.contains(NSPoint(x: parentFrame.midX, y: parentFrame.midY))
        } ?? NSScreen.main
        let frame = Self.reservedFrame(forSize: size, parentFrame: parentFrame, footprint: footprint,
                                       visible: host?.visibleFrame ?? footprint, gap: gap)
        panel.setFrame(frame, display: true)
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

    /// Pure placement for a card that must not cover its parent target. Tries the side
    /// of the footprint the parent lies on, then the others (horizontal sides first),
    /// keeping the first candidate fully inside `visible`. When none fits fully it
    /// picks the one showing most, clamped on screen; edge fallbacks beyond that are
    /// not modelled yet.
    static func reservedFrame(forSize size: NSSize, parentFrame: NSRect, footprint: NSRect,
                              visible: NSRect, gap: CGFloat) -> NSRect {
        let rightFirst = parentFrame.midX >= footprint.midX
        let topFirst = parentFrame.midY >= footprint.midY
        let right = NSRect(x: footprint.maxX + gap, y: parentFrame.midY - size.height / 2,
                           width: size.width, height: size.height)
        let left = NSRect(x: footprint.minX - gap - size.width, y: parentFrame.midY - size.height / 2,
                          width: size.width, height: size.height)
        let above = NSRect(x: parentFrame.midX - size.width / 2, y: footprint.maxY + gap,
                           width: size.width, height: size.height)
        let below = NSRect(x: parentFrame.midX - size.width / 2, y: footprint.minY - gap - size.height,
                           width: size.width, height: size.height)
        let candidates = (rightFirst ? [right, left] : [left, right])
            + (topFirst ? [above, below] : [below, above])

        func clamped(_ rect: NSRect) -> NSRect {
            var r = rect
            if visible.width >= r.width { r.origin.x = min(max(r.minX, visible.minX), visible.maxX - r.width) }
            else { r.origin.x = visible.minX }
            if visible.height >= r.height { r.origin.y = min(max(r.minY, visible.minY), visible.maxY - r.height) }
            else { r.origin.y = visible.minY }
            return r
        }

        var best: (frame: NSRect, shown: CGFloat)?
        for candidate in candidates {
            let moved = clamped(candidate)
            // A cross-axis clamp is fine; a clamp that pushes the card back into the
            // footprint (main axis lost) fails the footprint test and rejects it.
            let clearOfParent = !moved.intersects(parentFrame)
            if clearOfParent, visible.contains(moved), !moved.intersects(footprint) { return moved }
            let shown = candidate.intersection(visible)
            let area = shown.isNull ? 0 : shown.width * shown.height
            if clearOfParent, !moved.intersects(footprint), area > (best?.shown ?? -1) { best = (moved, area) }
        }
        return best?.frame ?? clamped(candidates[0])
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
