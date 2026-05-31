import AppKit
import SwiftUI

@MainActor
final class NotchWindowManager {
    private var panel: NotchPanel?
    private weak var notchViewModel: NotchViewModel?
    private let mediaViewModel: MediaViewModel
    private let hudViewModel: HUDViewModel
    private let hotkeyService = HotkeyService()

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

        // Provide hitTest rect (view-local coords, y-down)
        let capturedHUDVM = hudViewModel
        hostingView.interactiveRect = { [weak notchVM] in
            guard let vm = notchVM else { return .zero }
            // When a HUD is active the visible notch is hudWidth wide — match the hit zone.
            let isHUDActive = !vm.isExpanded && capturedHUDVM.currentHUD != nil
            let width: CGFloat = isHUDActive ? Constants.Notch.hudWidth : vm.targetInteractiveSize.width
            let height: CGFloat = vm.targetInteractiveSize.height
            let midX = Constants.Notch.canvasWidth / 2
            return CGRect(x: midX - width / 2, y: 0, width: width, height: height)
        }

        // Make layer opaque=false to avoid first-frame flash
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false

        self.panel = panel
        panel.orderFrontRegardless()

        // Start global hotkey (checks enabled flag on each keypress)
        hotkeyService.start { [weak self] in
            guard let vm = self?.notchViewModel else { return }
            if vm.isExpanded { vm.forceCollapse() } else { vm.expand() }
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
