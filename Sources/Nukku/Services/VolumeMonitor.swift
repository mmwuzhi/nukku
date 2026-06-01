import CoreAudio
import Foundation

/// Monitors the system default output device for volume and mute changes.
/// Automatically re-binds when the default output device changes (e.g. AirPods connect).
/// Callbacks are delivered on the main thread.
///
/// Note: CoreAudio listener blocks are C-level callbacks. Strict Swift 6
/// concurrency warnings in this file can be suppressed with @preconcurrency;
/// correctness is ensured by dispatching all state mutations via DispatchQueue.main.
final class VolumeMonitor: @unchecked Sendable {
    /// Called on main thread with (volume 0–1, isMuted).
    var onChange: @Sendable (Float, Bool) -> Void = { _, _ in }

    private var deviceID: AudioDeviceID = kAudioObjectUnknown
    // Stored so we can pass the identical blocks to Remove.
    private var volumeListenerBlock:       AudioObjectPropertyListenerBlock?
    private var muteListenerBlock:         AudioObjectPropertyListenerBlock?
    private var deviceChangeListenerBlock: AudioObjectPropertyListenerBlock?

    func start() {
        deviceID = resolveDefaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else { return }
        installListeners()
    }

    func stop() {
        guard deviceID != kAudioObjectUnknown else { return }
        removeListeners()
        deviceID = kAudioObjectUnknown
    }

    // MARK: - Read helpers (safe to call from any thread)

    func readVolume() -> Float {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope:    kAudioDevicePropertyScopeOutput,
            mElement:  kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &value)
        return value
    }

    func readMuted() -> Bool {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope:    kAudioDevicePropertyScopeOutput,
            mElement:  kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &value)
        return value != 0
    }

    // MARK: - Private

    private func resolveDefaultOutputDevice() -> AudioDeviceID {
        var id: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id
        )
        return id
    }

    private func installListeners() {
        let capturedDeviceID = deviceID
        let capturedOnChange = onChange   // copy the Sendable closure

        // Volume listener
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope:    kAudioDevicePropertyScopeOutput,
            mElement:  kAudioObjectPropertyElementMain
        )
        let volBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            let vol    = self.readVolume()
            let muted  = self.readMuted()
            DispatchQueue.main.async { capturedOnChange(vol, muted) }
        }
        volumeListenerBlock = volBlock
        AudioObjectAddPropertyListenerBlock(capturedDeviceID, &volAddr, nil, volBlock)

        // Mute listener
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope:    kAudioDevicePropertyScopeOutput,
            mElement:  kAudioObjectPropertyElementMain
        )
        let muteBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            let vol   = self.readVolume()
            let muted = self.readMuted()
            DispatchQueue.main.async { capturedOnChange(vol, muted) }
        }
        muteListenerBlock = muteBlock
        AudioObjectAddPropertyListenerBlock(capturedDeviceID, &muteAddr, nil, muteBlock)

        // Default device change listener — re-bind when e.g. AirPods connect
        var deviceAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        let deviceBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.deviceID != kAudioObjectUnknown else { return }
                self.stop()
                self.start()
            }
        }
        deviceChangeListenerBlock = deviceBlock
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &deviceAddr, nil, deviceBlock
        )
    }

    private func removeListeners() {
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope:    kAudioDevicePropertyScopeOutput,
            mElement:  kAudioObjectPropertyElementMain
        )
        if let b = volumeListenerBlock {
            AudioObjectRemovePropertyListenerBlock(deviceID, &volAddr, nil, b)
            volumeListenerBlock = nil
        }

        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope:    kAudioDevicePropertyScopeOutput,
            mElement:  kAudioObjectPropertyElementMain
        )
        if let b = muteListenerBlock {
            AudioObjectRemovePropertyListenerBlock(deviceID, &muteAddr, nil, b)
            muteListenerBlock = nil
        }

        var deviceAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        if let b = deviceChangeListenerBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &deviceAddr, nil, b
            )
            deviceChangeListenerBlock = nil
        }
    }
}
