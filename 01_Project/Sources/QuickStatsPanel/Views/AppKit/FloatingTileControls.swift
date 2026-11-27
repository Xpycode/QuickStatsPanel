#if DEBUG
import AppKit
import SwiftUI

/// Floating-tile HUD window. Borderless and non-activating: summoning orders it front without
/// making it key or activating the app. It can become key on a click inside it (still without
/// activating the app), which is how keyboard entry begins.
final class FloatingTileHUDPanel: NSPanel {
    /// False until a click lands inside the HUD, so ordering it front at summon can never make
    /// it key (AppKit may otherwise key a key-capable panel when the app has no key window).
    private(set) var keyboardEntryAllowed = false
    override var canBecomeKey: Bool { keyboardEntryAllowed }
    override var canBecomeMain: Bool { false }

    /// Keyboard entry without a click: used when the app itself is activated (for example by
    /// an accessibility client). Summoning never calls this, so it never takes focus by itself.
    func allowKeyboardEntry() {
        keyboardEntryAllowed = true
        if isVisible, !isKeyWindow { makeKey() }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            keyboardEntryAllowed = true
            // Key without activating the app (non-activating panel): the frontmost app stays active.
            if !isKeyWindow { makeKey() }
        }
        super.sendEvent(event)
    }
}

/// Draws SwiftUI without taking mouse events; the AppKit control beneath owns the click.
final class FloatingTileDrawingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// An interactive SwiftUI host (the detail card) whose first click is not swallowed by the
/// non-key panel.
final class FloatingTileInteractiveHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The flipped, transparent content view of the HUD. It draws nothing, so the window is fully
/// transparent between surfaces and the window server delivers clicks there to whatever lies
/// below (the gap counts as click-away under the existing pinning rule).
final class FloatingTileHostView: NSView {
    var contextMenuProvider: (() -> NSMenu)?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = contextMenuProvider?() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
        else { super.rightMouseDown(with: event) }
    }
}

/// Explicit AppKit navigation control for a tile, switcher item or group-bar action. Always a
/// key view (independent of the system Full Keyboard Access setting) so Tab/Shift-Tab traverse
/// the HUD; Return, Enter and Space activate; arrow keys are reported to the controller, which
/// moves by actual visual neighbours. SwiftUI draws the content beneath the focus ring.
final class FloatingTileButton: NSButton {
    let tileTarget: FloatingTileTarget
    var onActivate: ((FloatingTileTarget) -> Void)?
    var onArrow: ((FloatingTileTarget, FloatingTileDirection) -> Void)?
    var onFocus: ((FloatingTileTarget) -> Void)?
    /// Handle only: mouse-down starts a group drag instead of a click.
    var onDragStart: ((NSEvent) -> Void)?
    var cornerRadius: CGFloat = 6

    init<Content: View>(target: FloatingTileTarget, label: String, content: Content) {
        tileTarget = target
        super.init(frame: .zero)
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .noImage
        setButtonType(.momentaryChange)
        focusRingType = .exterior
        self.target = self
        action = #selector(clicked(_:))
        setAccessibilityLabel(label)
        let drawing = FloatingTileDrawingView(rootView: content)
        drawing.translatesAutoresizingMaskIntoConstraints = true
        drawing.autoresizingMask = [.width, .height]
        addSubview(drawing)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        subviews.forEach { $0.frame = bounds }
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { !isHiddenOrHasHiddenAncestor }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?(tileTarget) }
        return accepted
    }

    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }

    override func mouseDown(with event: NSEvent) {
        if let onDragStart { onDragStart(event); return }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 36, 76, 49: // Return, Enter, Space
            performClick(nil)
        case 123: onArrow?(tileTarget, .left)
        case 124: onArrow?(tileTarget, .right)
        case 125: onArrow?(tileTarget, .down)
        case 126: onArrow?(tileTarget, .up)
        default: super.keyDown(with: event)
        }
    }

    @objc private func clicked(_ sender: Any?) { onActivate?(tileTarget) }
}

/// Calm surface background shared by tiles, the switcher and the group bar.
struct FloatingTileSurface: View {
    var body: some View {
        let theme = AppSettings.shared.theme
        RoundedRectangle(cornerRadius: theme.metrics.cornerRadius, style: .continuous)
            .fill(theme.colors.background)
    }
}
#endif
