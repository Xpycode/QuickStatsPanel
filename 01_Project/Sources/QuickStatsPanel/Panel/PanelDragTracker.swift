import AppKit

/// Pointer tracking shared by the Strip, ring hub and fallback-list header. Moving
/// the frame directly avoids macOS's edge-triggered Space switching in performDrag.
@MainActor
enum PanelDragTracker {
    /// Returns the consumed mouse-up for callers whose gesture recognizer needs it.
    /// Ring input is handled directly and can ignore that event.
    @discardableResult
    static func track(_ panel: NSPanel) -> NSEvent? {
        let startPointer = NSEvent.mouseLocation
        let startOrigin = panel.frame.origin
        while panel.isVisible,
              let event = panel.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let pointer = NSEvent.mouseLocation
            var origin = NSPoint(x: startOrigin.x + pointer.x - startPointer.x,
                                 y: startOrigin.y + pointer.y - startPointer.y)
            if let visible = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })?.visibleFrame {
                if panel.frame.width <= visible.width {
                    origin.x = min(max(origin.x, visible.minX), visible.maxX - panel.frame.width)
                }
                if panel.frame.height <= visible.height {
                    origin.y = min(max(origin.y, visible.minY), visible.maxY - panel.frame.height)
                }
            }
            if origin != panel.frame.origin { panel.setFrameOrigin(origin) }
            if event.type == .leftMouseUp { return event }
        }
        return nil
    }
}
