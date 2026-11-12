#if DEBUG
import AppKit
import SwiftUI

/// Hosts the SwiftUI drawing without taking mouse events, so every click reaches
/// `RingInputView` (the superview) and is resolved against the shared geometry.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// One accessibility element per wedge, More and Settings.
final class RingAccessibilityElement: NSAccessibilityElement {
    var onPress: (@MainActor @Sendable () -> Void)?

    override func accessibilityPerformPress() -> Bool {
        guard let onPress else { return false }
        MainActor.assumeIsolated { onPress() }
        return true
    }
}

/// Content view of the ring panel: owns pointer input and accessibility, and draws
/// nothing itself. Hit testing uses the same `RingGeometry` the drawing consumes.
///
/// The panel is non-activating and never key, so `acceptsFirstMouse` is what lets the
/// first click on a wedge act while another app is frontmost. Activation happens on
/// mouse-up over the same target that received the mouse-down.
final class RingInputView: NSView {

    struct Description {
        let name: String
        let value: String
        let isAvailable: Bool
    }

    let geometry: RingGeometry
    /// Name / value / availability for a target, read live when accessibility asks.
    var describe: (RingTarget) -> Description = { _ in Description(name: "", value: "", isAvailable: true) }
    var onActivate: ((RingTarget) -> Void)?
    /// A click beyond the outer radius that still landed in this window (its
    /// transparent corners): treated as the outside click it looks like.
    var onOutsideClick: (() -> Void)?
    var contextMenuProvider: (() -> NSMenu)?

    private var pressed: RingTarget?

    init(geometry: RingGeometry) {
        self.geometry = geometry
        super.init(frame: NSRect(origin: .zero, size: geometry.size))
        setAccessibilityRole(.group)
        setAccessibilityLabel("Quick stats ring")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pressed = nil
        guard let target = geometry.target(at: point) else {
            if hypot(point.x - geometry.center.x, point.y - geometry.center.y) > RingGeometry.outerRadius {
                onOutsideClick?()
            }
            return
        }
        if target == .drag {
            // Native window drag. The ring panel has no move observer and nothing here
            // writes a position, so a drag never persists anything.
            window?.performDrag(with: event)
            return
        }
        pressed = target
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        let point = convert(event.locationInWindow, from: nil)
        guard let pressed, geometry.target(at: point) == pressed else { return }
        onActivate?(pressed)
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = contextMenuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { false }

    override func accessibilityChildren() -> [Any]? {
        var targets: [RingTarget] = geometry.wedges.map { .wedge($0.kind) }
        if geometry.moreFrame != nil { targets.append(.more) }
        targets.append(.settings)
        return targets.compactMap { target -> RingAccessibilityElement? in
            guard let frame = geometry.frame(of: target) else { return nil }
            let info = describe(target)
            let element = RingAccessibilityElement()
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(info.name)
            element.setAccessibilityValue(info.value)
            element.setAccessibilityEnabled(true)
            if !info.isAvailable { element.setAccessibilityHelp("No reading is available for this stat right now.") }
            element.setAccessibilityParent(self)
            element.setAccessibilityFrameInParentSpace(frame)
            element.onPress = { [weak self] in self?.onActivate?(target) }
            return element
        }
    }
}
#endif
