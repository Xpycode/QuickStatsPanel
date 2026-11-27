import AppKit

/// Pointer tracking shared by the Strip, ring hub and fallback-list header. Moving
/// the frame directly avoids macOS's edge-triggered Space switching in performDrag.
@MainActor
enum PanelDragTracker {
    /// Returns the consumed mouse-up for callers whose gesture recognizer needs it.
    /// Ring input is handled directly and can ignore that event.
    /// - Parameter keepVisible: the part of the window (window coordinates, bottom-left origin)
    ///   that must stay on screen; nil keeps the whole window on screen. Floating tiles pass
    ///   their visible group so the transparent detail envelope may run off the display.
    @discardableResult
    static func track(_ panel: NSPanel, keepVisible: NSRect? = nil) -> NSEvent? {
        let startPointer = NSEvent.mouseLocation
        let startOrigin = panel.frame.origin
        while panel.isVisible,
              let event = panel.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let pointer = NSEvent.mouseLocation
            var origin = NSPoint(x: startOrigin.x + pointer.x - startPointer.x,
                                 y: startOrigin.y + pointer.y - startPointer.y)
            if let visible = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })?.visibleFrame {
                let keep = keepVisible ?? NSRect(origin: .zero, size: panel.frame.size)
                if keep.width <= visible.width {
                    origin.x = min(max(origin.x, visible.minX - keep.minX), visible.maxX - keep.maxX)
                }
                if keep.height <= visible.height {
                    origin.y = min(max(origin.y, visible.minY - keep.minY), visible.maxY - keep.maxY)
                }
            }
            if origin != panel.frame.origin { panel.setFrameOrigin(origin) }
            if event.type == .leftMouseUp { return event }
        }
        return nil
    }
}
