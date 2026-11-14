#if DEBUG
import AppKit
import SwiftUI

/// Hosts the SwiftUI drawing without taking mouse events, so every click reaches
/// the input view (the superview) and is resolved against the shared geometry.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// One accessibility element per wedge, the More wedge, the gear or a list row.
final class RingAccessibilityElement: NSAccessibilityElement {
    var onPress: (@MainActor @Sendable () -> Void)?

    override func accessibilityPerformPress() -> Bool {
        guard let onPress else { return false }
        MainActor.assumeIsolated { onPress() }
        return true
    }
}

/// Mouse plumbing shared by every ring panel. Each panel forwards raw screen-space
/// events; the controller resolves them once against the frozen plan, so a click that
/// lands on a transparent corner of one panel but belongs to another panel's content
/// (or to an outside click) is handled identically whichever window the system delivered
/// it to.
///
/// The panels are non-activating and never key, so `acceptsFirstMouse` is what lets the
/// first click act while another app is frontmost.
class RingForwardingView: NSView {
    /// Screen point and the originating event (the drag needs it).
    var onMouseDown: ((NSPoint, NSEvent) -> Void)?
    var onMouseUp: ((NSPoint) -> Void)?
    var onScroll: ((NSPoint, CGFloat) -> Void)?
    var contextMenuProvider: (() -> NSMenu)?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func screenPoint(_ event: NSEvent) -> NSPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }

    override func mouseDown(with event: NSEvent) { onMouseDown?(screenPoint(event), event) }
    override func mouseUp(with event: NSEvent) { onMouseUp?(screenPoint(event)) }

    override func scrollWheel(with event: NSEvent) {
        // Wheel and trackpad deltas differ by an order of magnitude; precise ones are points.
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        onScroll?(screenPoint(event), -delta)
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = contextMenuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

/// Content view of the base ring panel. Hit testing and accessibility use the same
/// frozen `RingLayout` the drawing consumes.
final class RingInputView: RingForwardingView {

    struct Description {
        let name: String
        let value: String
        let isAvailable: Bool
        /// Whether the target's branch (detail or More) is open.
        var isExpanded = false
    }

    let snapshot: RingSnapshot
    /// Name / value / availability / expanded for a target, read live when accessibility asks.
    var describe: (RingTarget) -> Description = { _ in Description(name: "", value: "", isAvailable: true) }
    /// Accessibility Press: follows the same rules as a click.
    var onPress: ((RingTarget) -> Void)?

    init(snapshot: RingSnapshot) {
        self.snapshot = snapshot
        super.init(frame: NSRect(origin: .zero, size: snapshot.size))
        setAccessibilityRole(.group)
        setAccessibilityLabel("Quick stats ring")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func isAccessibilityElement() -> Bool { false }

    override func accessibilityChildren() -> [Any]? {
        var targets: [RingTarget] = snapshot.favourites.map { .wedge($0.kind) }
        if snapshot.layout.more != nil { targets.append(.more) }
        targets.append(.settings)
        return targets.compactMap { target -> RingAccessibilityElement? in
            guard let frame = snapshot.frame(of: target) else { return nil }
            let info = describe(target)
            let element = RingAccessibilityElement()
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(info.name)
            element.setAccessibilityValue(info.value)
            element.setAccessibilityEnabled(true)
            if target != .settings { element.setAccessibilityExpanded(info.isExpanded) }
            if !info.isAvailable { element.setAccessibilityHelp("No reading is available for this stat right now.") }
            element.setAccessibilityParent(self)
            element.setAccessibilityFrameInParentSpace(frame)
            element.onPress = { [weak self] in self?.onPress?(target) }
            return element
        }
    }
}

/// Content view of list panels (side More list, whole-list fallback). Draws nothing; its
/// accessibility children come from the controller.
final class RingSurfaceInputView: RingForwardingView {
    var accessibilityElementsProvider: (() -> [RingAccessibilityElement])?

    init(size: CGSize, label: String) {
        super.init(frame: NSRect(origin: .zero, size: size))
        setAccessibilityRole(.group)
        setAccessibilityLabel(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func isAccessibilityElement() -> Bool { false }

    override func accessibilityChildren() -> [Any]? {
        let elements = accessibilityElementsProvider?() ?? []
        elements.forEach { $0.setAccessibilityParent(self) }
        return elements
    }
}
#endif
