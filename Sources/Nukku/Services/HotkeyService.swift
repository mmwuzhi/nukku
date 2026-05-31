import AppKit

// Listens for a global keyboard shortcut and fires onActivate on the main actor.
// Requires Accessibility permission; macOS will prompt on first use.
@MainActor
final class HotkeyService {
    private var monitor: Any?

    func start(handler: @escaping @Sendable @MainActor () -> Void) {
        stop()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            // Extract Sendable values before crossing actor boundary.
            // Only check the four relevant modifiers; ignore CapsLock, NumPad, etc.
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let keyCode = event.keyCode
            Task { @MainActor in
                guard PreferencesManager.shared.hotkeyEnabled else { return }
                let (expectedFlags, expectedCode) = PreferencesManager.shared.hotkeyComponents()
                guard flags == expectedFlags, keyCode == expectedCode else { return }
                handler()
            }
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
