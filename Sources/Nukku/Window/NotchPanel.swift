import AppKit

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Pass mouse events through the transparent background area
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let result = super.hitTest(point) else { return nil }
        // If the hit view is just the bare contentView background, pass through
        if result === contentView { return nil }
        return result
    }
}
