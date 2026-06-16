import AppKit
import SwiftUI

/// Drag-to-shelf input for the FileDrop widget. Two cooperating windows:
///
/// 1. A small, always-present, transparent **detector** strip over the notch. It
///    receives the initial `draggingEntered` (the main panel can't: while collapsed
///    it is `ignoresMouseEvents = true`, and the hover poller that would flip it is
///    driven by a global `mouseMoved` monitor that AppKit silences during a drag).
/// 2. A larger **tray** window below the notch that is the visible drop affordance.
///    It is `orderOut` at rest (so it never swallows clicks) and `orderFront` only
///    while a drag is in flight. It is NEVER resized mid-drag — resizing the active
///    drag-destination window makes AppKit fire `draggingExited` (an expand/collapse
///    flicker we hit before), so it is created at its final size and just shown/hidden.
///
/// Neither window is routed through SkyLight: delegating a window into the SkyLight
/// layer stops it from receiving drag-destination events. The trade-off is that
/// drag-to-shelf does not work over native full-screen apps, an acceptable edge case.
@MainActor
final class NotchDropCatcher {
    var isEnabled: (() -> Bool)?
    var onDragEnter: (() -> Void)?
    var onDrop: (([URL]) -> Void)?
    var onDragEnd: (() -> Void)?

    private var detectorPanel: NSPanel?
    private var trayPanel: NSPanel?
    private var trayVisible = false
    private var hideWorkItem: DispatchWorkItem?

    func setup(detectorFrame: NSRect, trayFrame: NSRect, mainPanelLevel: NSWindow.Level) {
        // --- Detector strip (transparent, always present) ---
        let detector = NonConstrainingPanel(
            contentRect: detectorFrame,
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        detector.level             = NSWindow.Level(rawValue: mainPanelLevel.rawValue - 1)
        detector.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                       .fullScreenAuxiliary, .ignoresCycle]
        detector.backgroundColor   = .clear
        detector.isOpaque          = false
        detector.hasShadow         = false
        detector.isFloatingPanel   = true
        detector.becomesKeyOnlyIfNeeded = true
        detector.ignoresMouseEvents = false

        let detectorView = DropCatcherView()
        detectorView.isEnabled   = { [weak self] in self?.isEnabled?() ?? true }
        detectorView.onDragEnter = { [weak self] in self?.showTray() }
        detectorView.onDragMove  = { [weak self] in self?.keepTrayAlive() }
        detectorView.onDrop      = { [weak self] urls in self?.performDrop(urls) }
        detectorView.onDragEnd   = { [weak self] in self?.scheduleHideTray() }
        detector.contentView = detectorView
        detector.orderFrontRegardless()
        self.detectorPanel = detector

        // --- Tray (visible drop affordance, shown only during a drag) ---
        let tray = NonConstrainingPanel(
            contentRect: trayFrame,
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        tray.level             = NSWindow.Level(rawValue: mainPanelLevel.rawValue + 1)
        tray.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                   .fullScreenAuxiliary, .ignoresCycle]
        tray.backgroundColor   = .clear
        tray.isOpaque          = false
        tray.hasShadow         = false
        tray.isFloatingPanel   = true
        tray.becomesKeyOnlyIfNeeded = true
        tray.ignoresMouseEvents = false

        let trayView = NotchDropTrayView(
            onDrop: { [weak self] urls in self?.performDrop(urls) },
            onTargetedChange: { [weak self] targeted in
                if targeted { self?.keepTrayAlive() } else { self?.scheduleHideTray() }
            }
        )
        let hosting = NSHostingView(rootView: trayView)
        hosting.frame = NSRect(origin: .zero, size: trayFrame.size)
        hosting.autoresizingMask = [.width, .height]
        tray.contentView = hosting
        tray.orderOut(nil)
        self.trayPanel = tray
    }

    func updateFrames(detectorFrame: NSRect, trayFrame: NSRect) {
        detectorPanel?.setFrame(detectorFrame, display: false)
        // Safe: the tray is only resized while hidden (between drags).
        if !trayVisible { trayPanel?.setFrame(trayFrame, display: false) }
    }

    func teardown() {
        hideWorkItem?.cancel()
        detectorPanel?.close()
        trayPanel?.close()
        detectorPanel = nil
        trayPanel = nil
    }

    // MARK: - Tray show/hide (debounced)

    private func showTray() {
        keepTrayAlive()
        guard !trayVisible else { return }
        trayVisible = true
        trayPanel?.orderFrontRegardless()
        onDragEnter?()
    }

    private func keepTrayAlive() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    /// Debounced hide: bridges the moment the cursor leaves the detector strip and
    /// lands on the tray (or vice-versa) without retracting the tray between them.
    private func scheduleHideTray() {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideTray() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func hideTray() {
        guard trayVisible else { return }
        trayVisible = false
        trayPanel?.orderOut(nil)
        onDragEnd?()
    }

    private func performDrop(_ urls: [URL]) {
        keepTrayAlive()
        onDrop?(urls)
        hideTray()
    }
}

/// The detector strip's drag-destination view. Transparent; reports drag lifecycle
/// back to the catcher via closures.
private final class DropCatcherView: NSView {
    var isEnabled: (() -> Bool)?
    var onDragEnter: (() -> Void)?
    var onDragMove: (() -> Void)?
    var onDrop: (([URL]) -> Void)?
    var onDragEnd: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func acceptsDrag(_ sender: NSDraggingInfo) -> Bool {
        (isEnabled?() ?? true) && sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptsDrag(sender) else { return [] }
        onDragEnter?()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptsDrag(sender) else { return [] }
        onDragMove?()
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty else {
            return false
        }
        onDrop?(urls)
        return true
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragEnd?()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDragEnd?()
    }
}

/// AppKit clamps windows to the screen's `visibleFrame` (below the menu bar) by
/// default, which would push these windows out of the notch band. Return the
/// requested frame unchanged, mirroring `NotchPanel`.
private final class NonConstrainingPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
