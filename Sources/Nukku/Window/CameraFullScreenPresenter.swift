import AppKit
import SwiftUI

@MainActor
final class CameraFullScreenPresenter {
    private var panel: CameraFullScreenPanel?

    func present(viewModel: CameraViewModel, onDismiss: @escaping @MainActor () -> Void) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
        guard let screen else { return }

        let panel = CameraFullScreenPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.setFrame(screen.frame, display: true)

        let content = CameraFullScreenView()
            .environment(viewModel)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        panel.onDismiss = { [weak self] in
            self?.panel = nil
            onDismiss()
        }

        self.panel = panel
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        guard let panel else { return }
        self.panel = nil
        panel.onDismiss = nil
        panel.close()
    }
}

final class CameraFullScreenPanel: NSPanel {
    var onDismiss: (@MainActor () -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
        } else {
            super.keyDown(with: event)
        }
    }

    override func close() {
        super.close()
        onDismiss?()
    }
}
