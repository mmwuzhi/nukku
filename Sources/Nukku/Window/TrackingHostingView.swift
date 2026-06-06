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

    /// Gate: pass clicks only if they land inside the visible silhouette.
    override func hitTest(_ point: NSPoint) -> NSView? {
        // point arrives in the superview's coordinate system.
        // For the contentView (no superview) that is window coordinates (y-up).
        // convert(from: nil) flips to view-local coordinates (y-down, isFlipped=true).
        let local = convert(point, from: nil)
        return interactiveRect().contains(local) ? super.hitTest(point) : nil
    }

    // MARK: - Cursor management dead ends
    //
    // Goal: show a pointing-hand cursor over interactive controls (e.g. the
    // Media widget's play/pause button) instead of letting the underlying
    // app's cursor (often I-beam over a text editor) bleed through.
    //
    // Why this is hard for us: Nukku's NSPanel is non-activating
    // (becomesKeyOnlyIfNeeded = true, .canJoinAllSpaces, high level). It
    // doesn't hold cursor authority — the OS keeps querying the underlying
    // app for cursorUpdate and that wins each mouseMoved (1 kHz mouse rate).
    //
    // Approaches tried, in order, and why each failed on macOS 26:
    //   1. SwiftUI .pointerStyle(.link)         — never propagates to the system
    //                                              cursor manager from this panel
    //   2. SwiftUI .onHover + NSCursor.push/pop — push gets overridden by the
    //                                              next mouseMoved from below
    //   3. 30 Hz Timer + NSCursor.set()         — mouse moves at ~1 kHz, our
    //                                              set is overridden between ticks
    //   4. AppKit addCursorRect (resetCursorRects) — cursor rects need a key
    //                                              window; ours isn't
    //   5. NSTrackingArea + .cursorUpdate       — fires on enter/exit only;
    //                                              re-entries into SwiftUI button
    //                                              subviews use their own (default)
    //                                              cursor
    //   6. Above + .mouseMoved + manual re-claim — still loses on most controls
    //
    // Decision: do not run cursor-claiming code here. The Media widget's UX
    // was redesigned (single big ⏯ button, marquee title) so the cursor cue
    // is no longer load-bearing; half-working cursor hacks cause more uncanny
    // behavior than a plain arrow/I-beam inherited from the underlying app.
    //
    // If a future macOS release re-grants cursor authority to non-activating
    // panels, approaches 4 (addCursorRect) or 1 (pointerStyle) would be the
    // cleanest to revisit.

}
