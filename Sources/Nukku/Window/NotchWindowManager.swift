import AppKit
import SwiftUI

@MainActor
final class NotchWindowManager {
    private var panel: NotchPanel?
    private weak var notchViewModel: NotchViewModel?
    private let mediaViewModel: MediaViewModel
    private let hudViewModel: HUDViewModel

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
        hostingView.interactiveRect = { [weak notchVM] in
            guard let vm = notchVM else { return .zero }
            let size = vm.targetInteractiveSize
            let midX = Constants.Notch.canvasWidth / 2
            // y = 0 at top (isFlipped = true)
            return CGRect(x: midX - size.width / 2,
                          y: 0,
                          width:  size.width,
                          height: size.height)
        }

        // Make layer opaque=false to avoid first-frame flash
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false

        self.panel = panel
        panel.orderFrontRegardless()
    }

    // MARK: - Reposition (screen change only, no animation)

    func repositionWindow() {
        guard let screen = primaryScreen(), let panel else { return }

        let actualCollapsedH = screen.hasNotch
            ? screen.safeAreaInsets.top
            : NSStatusBar.system.thickness
        notchViewModel?.collapsedHeight = actualCollapsedH

        panel.setFrame(canvasFrame(for: screen), display: false)
    }

    func teardown() {
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
