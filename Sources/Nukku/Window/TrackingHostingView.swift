import AppKit
import SwiftUI

/// NSHostingView subclass that gates mouse events to the current notch shape.
/// The window is a large fixed canvas; areas outside the notch silhouette
/// pass clicks through to whatever is behind (menu bar icons, apps, etc.).
///
/// Hover detection is handled entirely by SwiftUI's `.onHover` / `.contentShape`
/// in `NotchContainerView` — no NSTrackingArea needed here.
@MainActor
final class NotchHostingView<Content: View>: NSHostingView<Content> {

    /// Returns the interactive rect in the receiver's own coordinate space
    /// (top-left origin because NSHostingView.isFlipped == true).
    /// Updated by NotchWindowManager whenever state changes.
    var interactiveRect: () -> CGRect = { .zero }

    /// Gate: pass clicks only if they land inside the notch silhouette.
    override func hitTest(_ point: NSPoint) -> NSView? {
        // point arrives in the superview's coordinate system.
        // For the contentView (no superview) that is window coordinates (y-up).
        // convert(from: nil) flips to view-local coordinates (y-down, isFlipped=true).
        let local = convert(point, from: nil)
        return interactiveRect().contains(local) ? super.hitTest(point) : nil
    }
}
