import Foundation
import IOKit

/// Polls display brightness via IOKit and fires `onChange` when it changes.
/// Polling avoids CoreDisplay private API. Delivered on main thread.
final class BrightnessMonitor {
    var onChange: @Sendable (Float) -> Void = { _ in }

    private var lastBrightness: Float = -1
    private var timer: DispatchSourceTimer?

    func start() {
        timer?.cancel()  // guard against double-start leaking an active DispatchSourceTimer
        let capturedOnChange = onChange  // capture Sendable closure once; safe to read from bg
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + 0.25, repeating: 0.25)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let current = self.readBrightness()
            guard abs(current - self.lastBrightness) > 0.005 else { return }
            self.lastBrightness = current
            DispatchQueue.main.async { capturedOnChange(current) }
        }
        t.activate()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        lastBrightness = -1
    }

    func readBrightness() -> Float {
        readIOKitBrightness() ?? 1.0
    }

    // MARK: - Private

    private func readIOKitBrightness() -> Float? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var brightness: Float = 0
        let kr = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness)
        guard kr == kIOReturnSuccess else { return nil }
        return brightness
    }
}
