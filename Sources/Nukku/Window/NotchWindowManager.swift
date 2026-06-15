import AppKit
import SkyLightWindow
import SwiftUI

@MainActor
final class NotchWindowManager {
    private var panel: NotchPanel?
    private weak var notchViewModel: NotchViewModel?
    private let mediaViewModel: MediaViewModel
    private let hudViewModel: HUDViewModel
    private let hotkeyService = HotkeyService()

    // Cursor tracking for hover detection + click-through gating. A global
    // mouse-move monitor starts a 15 Hz poller only while the pointer is near
    // the top-center screen band.
    private var mouseTimer: Timer?
    private var mouseMoveMonitor: Any?
    private var mouseDownMonitor: Any?
    private var isCursorInHoverZone: Bool = false
    private var isMouseTrackingActive: Bool = false

    // App that held key-window status before the panel took it on expand, so we
    // can hand focus back on collapse.
    private var appBeforeKey: NSRunningApplication?

    init(notchViewModel: NotchViewModel, mediaViewModel: MediaViewModel, hudViewModel: HUDViewModel) {
        self.notchViewModel = notchViewModel
        self.mediaViewModel = mediaViewModel
        self.hudViewModel   = hudViewModel
    }

    // MARK: - Setup

    func setupWindow() {
        guard let screen = primaryScreen() else { return }

        // Read actual notch height from screen and store in ViewModel
        let actualCollapsedH = screen.hasNotch
            ? screen.safeAreaInsets.top
            : NSStatusBar.system.thickness
        notchViewModel?.collapsedHeight = actualCollapsedH
        if screen.hasNotch { notchViewModel?.collapsedWidth = screen.notchWidth }

        let frame = canvasFrame(for: screen)

        let panel = NotchPanel(
            contentRect: frame,
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )

        // Float above the menu bar, follow all Spaces including full-screen apps
        panel.level            = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor  = .clear
        panel.isOpaque         = false
        panel.hasShadow        = false
        panel.isFloatingPanel  = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false

        // Build SwiftUI tree
        guard let notchVM = notchViewModel else { return }
        let content = NotchContainerView()
            .environment(notchVM)
            .environment(mediaViewModel)
            .environment(hudViewModel)

        let hostingView = NotchHostingView(rootView: content)
        hostingView.frame = NSRect(
            origin: .zero,
            size: CGSize(width: Constants.Notch.canvasWidth,
                         height: Constants.Notch.canvasHeight)
        )
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        // Click hit-test rect (view-local, y-down) — matches the full visible silhouette so
        // any click on the notch passes through to SwiftUI.
        let capturedHUDVM = hudViewModel
        hostingView.interactiveRect = { [weak notchVM] in
            guard let vm = notchVM else { return .zero }
            _ = capturedHUDVM // keep HUD VM captured so updates invalidate closure dependencies
            let width: CGFloat = vm.targetInteractiveSize.width
            let height: CGFloat = vm.targetInteractiveSize.height
            let midX = Constants.Notch.canvasWidth / 2
            return CGRect(x: midX - width / 2, y: 0, width: width, height: height)
        }

        // Make layer opaque=false to avoid first-frame flash
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false

        self.panel = panel
        panel.ignoresMouseEvents = true   // start in pass-through mode; toggled by mouse monitor
        panel.orderFrontRegardless()

        // Float above native full-screen apps via private SkyLight APIs (no public API
        // can render over another app's full-screen notch/menubar bar). Must run after
        // orderFront so the window has a valid windowNumber. Keeps the existing panel,
        // hit-testing, and mouse monitors intact.
        SkyLightOperator.shared.delegateWindow(panel)

        startMouseMonitor()

        // Take key-window status while expanded so the notch owns the cursor
        // (a non-key panel loses cursor control to the app behind it), then hand
        // focus back on collapse.
        notchViewModel?.onExpandedChange = { [weak self] expanded in
            self?.setPanelKey(expanded)
        }

        // Start global hotkey (checks enabled flag on each keypress)
        hotkeyService.start { [weak self] in
            guard let vm = self?.notchViewModel else { return }
            if vm.isExpanded { vm.forceCollapse() } else { vm.expand() }
        }
    }

    // MARK: - Mouse monitor (hover + click-through gating)
    //
    // SwiftUI .onHover uses the view frame (whole 700×340 canvas) and can't be narrowed
    // by .contentShape. NSHostingView's internal tracking covers the whole hosting view.
    // To get a tight hover zone AND let clicks pass through to menu-bar items adjacent
    // to the notch, the app samples NSEvent.mouseLocation at 15 Hz only while the pointer
    // is near the top-center screen band.
    //
    //  - cursor inside interactiveZone() → panel ignoresMouseEvents = false (panel can be clicked)
    //  - cursor inside expandZone()      → schedule expand
    //  - cursor outside expandZone()     → cancel expand / start collapse
    //
    // The two zones intentionally differ in collapsed media state: the right
    // shelf is a transport control, so it remains clickable without becoming
    // an accidental hover-to-expand trigger.

    private func startMouseMonitor() {
        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in self?.updateMouseTrackingActivation() }
        }
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.handleGlobalMouseDown() }
        }

        panel?.handleLeftMouseDownInScreen = { [weak self] point in
            guard let self else { return false }
            return self.handlePanelLeftMouseDown(at: point)
        }
    }

    private func stopMouseMonitor() {
        mouseTimer?.invalidate()
        mouseTimer = nil
        if let mouseMoveMonitor {
            NSEvent.removeMonitor(mouseMoveMonitor)
            self.mouseMoveMonitor = nil
        }
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
            self.mouseDownMonitor = nil
        }
        isMouseTrackingActive = false
    }

    private func startTopRegionPollingIfNeeded() {
        guard mouseTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.handleMouseMove() }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
        isMouseTrackingActive = true
        handleMouseMove()
    }

    private func stopTopRegionPolling() {
        mouseTimer?.invalidate()
        mouseTimer = nil
        isMouseTrackingActive = false
        isCursorInHoverZone = false
        mediaViewModel.isHoveringTransportControl = false
        notchViewModel?.cancelHoverExpand()
        notchViewModel?.collapse()
        panel?.ignoresMouseEvents = true
    }

    private func updateMouseTrackingActivation() {
        let cursor = NSEvent.mouseLocation
        if isNearTopRegion(cursor) {
            startTopRegionPollingIfNeeded()
        } else if isMouseTrackingActive {
            stopTopRegionPolling()
        }
    }

    private func isNearTopRegion(_ cursor: CGPoint) -> Bool {
        guard let screen = primaryScreen(), abs(cursor.x - screen.frame.midX) <= Constants.Notch.canvasWidth / 2 else {
            return false
        }
        let activeHeight = currentInteractiveZoneScreenRect().height + 42
        let topBandHeight = (isMouseTrackingActive || notchViewModel?.isExpanded == true)
            ? max(90, activeHeight)
            : 90
        return cursor.y >= screen.frame.maxY - topBandHeight
    }

    /// Returns the visible/clickable zone in *screen* coordinates (bottom-origin).
    /// Tracks the current silhouette so adjacent menu-bar items remain clickable.
    private func currentInteractiveZoneScreenRect() -> CGRect {
        guard let panel, let vm = notchViewModel else { return .zero }
        let metrics = vm.currentMetrics
        let baseWidth = max(metrics.topWidth, metrics.bodyWidth)
        let baseHeight = metrics.height
        let xInset: CGFloat
        if vm.isExpanded {
            xInset     = 0
        } else if hudViewModel.currentHUD != nil {
            xInset     = 0
        } else {
            xInset     = 6
        }

        let width  = max(0, baseWidth - xInset * 2)
        // Extend top by 2pt so cursor at the very top edge of the screen still counts
        // (CGRect.contains uses [y, y+height) and would otherwise exclude the upper edge).
        let topPad: CGFloat = 2
        let panelFrame = panel.frame
        return CGRect(
            x: panelFrame.midX - width / 2,
            y: panelFrame.maxY - baseHeight,
            width:  width,
            height: baseHeight + topPad
        )
    }

    /// Returns the hover-to-expand trigger zone. It is usually the same as the
    /// clickable zone, except collapsed media controls exclude the right shelf
    /// so aiming for play/pause does not open the panel.
    private func currentExpandZoneScreenRect() -> CGRect {
        guard let vm = notchViewModel else { return .zero }
        var rect = currentInteractiveZoneScreenRect()
        guard vm.presentationMode == .rest, mediaViewModel.hasMediaSession else {
            return rect
        }
        let rightControlWidth: CGFloat = 58
        rect.size.width = max(0, rect.width - rightControlWidth)
        return rect
    }

    private func currentTransportControlZoneScreenRect() -> CGRect {
        guard let vm = notchViewModel,
              vm.presentationMode == .rest,
              mediaViewModel.hasMediaSession else {
            return .zero
        }
        let interactive = currentInteractiveZoneScreenRect()
        let rightControlWidth: CGFloat = 58
        return CGRect(
            x: interactive.maxX - rightControlWidth,
            y: interactive.minY,
            width: rightControlWidth,
            height: interactive.height
        )
    }

    private func handleMouseMove() {
        guard let panel, let vm = notchViewModel else { return }
        let cursor = NSEvent.mouseLocation  // screen coords, bottom-origin
        guard isNearTopRegion(cursor) else {
            stopTopRegionPolling()
            return
        }
        let insideInteractiveZone = currentInteractiveZoneScreenRect().contains(cursor)
        let insideExpandZone = currentExpandZoneScreenRect().contains(cursor)
        let insideTransportControl = currentTransportControlZoneScreenRect().contains(cursor)
        // Always update panel.ignoresMouseEvents for click-through behavior.
        panel.ignoresMouseEvents = !insideInteractiveZone
        mediaViewModel.isHoveringTransportControl = insideTransportControl

        guard insideExpandZone != isCursorInHoverZone else { return }
        isCursorInHoverZone = insideExpandZone
        if insideExpandZone {
            vm.scheduleHoverExpand()
        } else {
            vm.cancelHoverExpand()
            vm.collapse()
        }
    }

    private func handlePanelLeftMouseDown(at point: CGPoint) -> Bool {
        guard currentTransportControlZoneScreenRect().contains(point) else { return false }
        mediaViewModel.togglePlayPause()
        handleMouseMove()
        return true
    }

    private func handleGlobalMouseDown() {
        let cursor = NSEvent.mouseLocation
        guard currentTransportControlZoneScreenRect().contains(cursor) else { return }
        mediaViewModel.togglePlayPause()
        handleMouseMove()
    }

    // MARK: - Key-window handoff (cursor authority while expanded)

    private func setPanelKey(_ shouldBeKey: Bool) {
        guard let panel else { return }
        if shouldBeKey {
            // Only an explicit click-to-expand grants key-window status. On the
            // default hover trigger the panel must stay non-key so passive hovering
            // never swallows the front app's keyboard input. Click users still get
            // native per-control cursors once the panel is key.
            guard PreferencesManager.shared.expandTrigger == .click else { return }
            guard !panel.isKeyWindow else { return }
            // Remember who had focus so we can restore it on collapse. We are a
            // non-activating accessory app, so this is always the user's app.
            appBeforeKey = NSWorkspace.shared.frontmostApplication
            panel.makeKey()
        } else {
            // Returning key to the previous app also resigns ours.
            if panel.isKeyWindow, let appBeforeKey {
                appBeforeKey.activate()
            }
            appBeforeKey = nil
        }
    }

    // MARK: - Reposition (screen change only, no animation)

    func repositionWindow() {
        guard let screen = primaryScreen(), let panel else { return }

        let actualCollapsedH = screen.hasNotch
            ? screen.safeAreaInsets.top
            : NSStatusBar.system.thickness
        notchViewModel?.collapsedHeight = actualCollapsedH
        if screen.hasNotch { notchViewModel?.collapsedWidth = screen.notchWidth }

        panel.setFrame(canvasFrame(for: screen), display: false)
    }

    func teardown() {
        hotkeyService.stop()
        stopMouseMonitor()
        panel?.handleLeftMouseDownInScreen = nil
        panel?.close()
        panel = nil
    }

    // MARK: - Helpers

    /// Prefer the built-in notch screen; fall back to main.
    private func primaryScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    /// Fixed canvas frame: always the same size, pinned to the top of the chosen screen.
    private func canvasFrame(for screen: NSScreen) -> NSRect {
        let sf = screen.frame
        return NSRect(
            x: sf.midX - Constants.Notch.canvasWidth / 2,
            y: sf.maxY - Constants.Notch.canvasHeight,
            width:  Constants.Notch.canvasWidth,
            height: Constants.Notch.canvasHeight
        )
    }
}
