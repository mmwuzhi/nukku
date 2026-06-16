import AppKit
import SwiftUI

/// NSHostingView subclass that gates click events to the current notch silhouette.
///
/// Hover detection is **not** handled here — it lives in `NotchWindowManager` via
/// global/local NSEvent monitors. That's the only way to get a hover zone narrower
/// than the panel's full canvas (SwiftUI .onHover uses the view's frame; NSHostingView's
/// own tracking areas cover the whole canvas; .contentShape doesn't gate hover).
///
/// Click-through to menu-bar items adjacent to the notch is achieved by toggling the
/// panel's `ignoresMouseEvents` based on cursor position, also driven from the same
/// monitor in NotchWindowManager.
@MainActor
final class NotchHostingView<Content: View>: NSHostingView<Content> {

    /// Click hit-test rect in view-local coords (top-left origin). Drop click events
    /// that fall outside the visible silhouette.
    var interactiveRect: () -> CGRect = { .zero }

    /// macOS auto-inset (safeAreaInsets.top = 38pt on notched MBPs) would push the
    /// notch silhouette below the menubar — pin to zero so content draws from the
    /// very top of the canvas.
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    /// Deliver the first click to the control even when the panel is non-key.
    /// In hover mode the panel never becomes key, so without this every click is
    /// treated as a window-activating "first mouse" and swallowed, making tabs and
    /// buttons feel unresponsive (needing a second click).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Gate: pass clicks only if they land inside the visible silhouette.
    override func hitTest(_ point: NSPoint) -> NSView? {
        // point arrives in the superview's coordinate system.
        // For the contentView (no superview) that is window coordinates (y-up).
        // convert(from: nil) flips to view-local coordinates (y-down, isFlipped=true).
        let local = convert(point, from: nil)
        return interactiveRect().contains(local) ? super.hitTest(point) : nil
    }

    // MARK: - Cursor authority
    //
    // The cursor seen inside the panel is owned by whichever window is *key*.
    // A non-key window cannot win cursor management against the key app, so any
    // view-level claim here (cursorUpdate / mouseMoved / addCursorRect / timed
    // NSCursor.set) loses to the underlying app and its I-beam/link cursor bleeds
    // through. The only fix is to make the panel key, which NotchWindowManager
    // does on expand (see `setPanelKey`). Once key, SwiftUI manages per-control
    // cursors natively (hand on buttons, arrow elsewhere), so no code is needed
    // here.

}
