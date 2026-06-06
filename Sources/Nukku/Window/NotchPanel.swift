import AppKit

final class NotchPanel: NSPanel {
    var handleLeftMouseDownInScreen: ((CGPoint) -> Bool)?

    override var canBecomeKey:  Bool { true  }
    override var canBecomeMain: Bool { false }

    /// AppKit constrains windows to the screen's visibleFrame (below the menubar) by default.
    /// We need the panel to span up into the hardware-notch area, so return the requested
    /// frame unchanged.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           let screenPoint = event.window?.convertPoint(toScreen: event.locationInWindow),
           handleLeftMouseDownInScreen?(screenPoint) == true {
            return
        }
        super.sendEvent(event)
    }
}
