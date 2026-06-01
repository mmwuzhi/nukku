import AppKit

final class NotchPanel: NSPanel {
    override var canBecomeKey:  Bool { true  }
    override var canBecomeMain: Bool { false }

    /// AppKit constrains windows to the screen's visibleFrame (below the menubar) by default.
    /// We need the panel to span up into the hardware-notch area, so return the requested
    /// frame unchanged.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
