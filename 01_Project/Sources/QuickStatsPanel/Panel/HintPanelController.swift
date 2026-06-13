import AppKit
import SwiftUI

/// Shows the one-time first-run hint card in a borderless, non-activating
/// `NSPanel` beneath the strip — the same sibling-panel pattern as
/// `DetailPanelController` (D-001 / D-015): flat `Theme` card, floating level,
/// never steals focus, sized once on open.
///
/// **Why a hint at all:** this is an `LSUIElement` agent app — no Dock icon, no
/// menu-bar item (D-003). Once the auto-summoned strip dismisses, the global
/// hotkey is the *only* way back, and a first-time user has no way to discover it.
/// So on the very first launch we show this card teaching the hotkey.
///
/// Lifecycle is deliberately thin: it has no toggle and no dismiss control of its
/// own. `AppDelegate` shows it once beneath the strip on first launch, and tears
/// it down via the strip's existing `onVisibilityChanged` broadcast — so the card
/// vanishes with the strip on *every* hide path (Esc / toggle / click-away),
/// exactly like the detail card, with no new dismissal code.
@MainActor
final class HintPanelController {

    private var panel: NSPanel?
    private var hosting: NSHostingView<AnyView>?

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Gap between the strip's edge and the hint card (matches the detail card).
    private let gap: CGFloat = 6

    /// Show `content` centered beneath the strip. `stripFrame` is the strip
    /// panel's on-screen frame. Measured once now — it won't resize while open.
    func show<Content: View>(stripFrame: NSRect, @ViewBuilder content: () -> Content) {
        let hosting = NSHostingView(rootView: AnyView(content()))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = self.panel ?? makePanel(size: size)
        panel.contentView = hosting

        let origin = origin(forSize: size, stripFrame: stripFrame)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()

        self.hosting = hosting
        self.panel = panel
    }

    func hide() {
        guard panel != nil else { return }
        panel?.orderOut(nil)
        panel = nil
        hosting = nil
    }

    // MARK: - Geometry

    /// Center the card under the strip and sit it just below; if it would fall off
    /// the bottom of the screen, flip it above the strip, then clamp on-screen.
    /// (Same rules as `DetailPanelController`, minus the click-anchor — the hint
    /// centers on the strip, not on a tap point.)
    private func origin(forSize size: NSSize, stripFrame: NSRect) -> NSPoint {
        let host = NSScreen.screens.first {
            $0.frame.contains(NSPoint(x: stripFrame.midX, y: stripFrame.midY))
        } ?? NSScreen.main
        let visible = host?.visibleFrame ?? stripFrame

        var x = stripFrame.midX - size.width / 2
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
