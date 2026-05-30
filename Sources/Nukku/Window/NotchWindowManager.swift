import AppKit
import SwiftUI

@MainActor
final class NotchWindowManager {
    private var panel: NotchPanel?
    private let notchViewModel: NotchViewModel
    private let mediaViewModel: MediaViewModel

    init(notchViewModel: NotchViewModel, mediaViewModel: MediaViewModel) {
        self.notchViewModel = notchViewModel
        self.mediaViewModel = mediaViewModel
    }

    func setupWindow() {
        guard let screen = NSScreen.main else { return }
        let frame = windowFrame(for: screen, width: Constants.Notch.defaultWidth, height: Constants.Notch.defaultHeight)

        let panel = NotchPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Sit just above the status bar so it overlaps the notch area
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false

        let contentView = NotchContainerView()
            .environment(notchViewModel)
            .environment(mediaViewModel)

        let hostingView = TrackingHostingView(rootView: contentView)
        hostingView.frame = panel.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        hostingView.onMouseEntered = { [weak self] in
            self?.notchViewModel.expand()
        }
        hostingView.onMouseExited = { [weak self] in
            self?.notchViewModel.collapse()
        }

        self.panel = panel

        // Observe ViewModel size changes to resize the panel
        observeSizeChanges()

        panel.orderFrontRegardless()
    }

    private func observeSizeChanges() {
        // Poll via a periodic check using a retained reference
        // We use a simple observation via withObservationTracking
        scheduleObservation()
    }

    private func scheduleObservation() {
        withObservationTracking {
            _ = notchViewModel.notchWidth
            _ = notchViewModel.notchHeight
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.syncPanelFrame()
                self?.scheduleObservation()
            }
        }
    }

    func syncPanelFrame() {
        guard let screen = NSScreen.main, let panel else { return }
        let frame = windowFrame(
            for: screen,
            width: notchViewModel.notchWidth,
            height: notchViewModel.notchHeight
        )
        panel.setFrame(frame, display: true)
    }

    func repositionWindow() {
        syncPanelFrame()
    }

    func teardown() {
        panel?.close()
        panel = nil
    }

    // MARK: - Frame Calculation

    private func windowFrame(for screen: NSScreen, width: CGFloat, height: CGFloat) -> NSRect {
        let screenFrame = screen.frame
        // safeAreaInsets.top > 0 means notch machine; fall back to menu bar thickness
        let anchorHeight = screen.hasNotch
            ? screen.safeAreaInsets.top
            : NSStatusBar.system.thickness

        // Center the panel horizontally; expand downward from the top edge
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - anchorHeight - (height - anchorHeight).clamped(to: 0...)

        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private extension Comparable {
    func clamped(to range: PartialRangeFrom<Self>) -> Self {
        max(self, range.lowerBound)
    }
}
