import IOKit.ps
import Foundation

// Fires onChange only when charging state flips (plug in / pull out).
// Callback is delivered on the main thread.
// @unchecked Sendable: all access is confined to the main run loop.
final class BatteryMonitor: @unchecked Sendable {
    var onChange: @Sendable (Float, Bool) -> Void = { _, _ in }

    private var runLoopSource: CFRunLoopSource?
    nonisolated(unsafe) private var lastIsCharging: Bool? = nil
    nonisolated(unsafe) private var retainedSelf: Unmanaged<BatteryMonitor>? = nil

    func start() {
        guard retainedSelf == nil else { return }
        lastIsCharging = readState()?.isCharging

        let retained = Unmanaged.passRetained(self)
        retainedSelf = retained

        let src = IOPSNotificationCreateRunLoopSource({ ptr in
            guard let ptr else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(ptr).takeUnretainedValue().handleChange()
        }, retained.toOpaque())

        if let src = src?.takeRetainedValue() {
            runLoopSource = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }

    func stop() {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
            runLoopSource = nil
        }
        retainedSelf?.release()
        retainedSelf = nil
        lastIsCharging = nil
    }

    // MARK: - Private

    private func handleChange() {
        guard let state = readState() else { return }
        guard state.isCharging != lastIsCharging else { return }
        lastIsCharging = state.isCharging
        let capturedOnChange = onChange
        DispatchQueue.main.async { capturedOnChange(state.level, state.isCharging) }
    }

    private func readState() -> (level: Float, isCharging: Bool)? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        guard let source = list.first,
              let desc = IOPSGetPowerSourceDescription(info, source)
                .takeUnretainedValue() as? [String: Any],
              let capacity    = desc[kIOPSCurrentCapacityKey] as? Int,
              let maxCapacity = desc[kIOPSMaxCapacityKey] as? Int
        else { return nil }

        let isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
        let level = Float(capacity) / Float(max(maxCapacity, 1))
        return (level, isCharging)
    }
}
