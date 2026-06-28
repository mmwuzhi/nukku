import CoreAudio
import AudioToolbox
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
    private var volumeListeners:           [PropertyListenerRegistration] = []
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
        guard deviceID != kAudioObjectUnknown else { return 0 }
        if let volume = readFloat(volumeAddress(.virtualMain)) {
            return volume
        }
        let channels = readableVolumeScalarElements()
        guard !channels.isEmpty else { return 0 }
        let total = channels.reduce(Float(0)) { partial, element in
            partial + (readFloat(volumeAddress(.scalar(element))) ?? 0)
        }
        return total / Float(channels.count)
    }

    func readMuted() -> Bool {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope:    kAudioDevicePropertyScopeOutput,
            mElement:  kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &value)
        guard status == noErr else { return false }
        return value != 0
    }

    @discardableResult
    func setVolume(_ volume: Float) -> Float {
        guard deviceID != kAudioObjectUnknown else { return 0 }
        let clamped = max(0, min(1, volume))
        if !setFloat(clamped, at: volumeAddress(.virtualMain)) {
            let channels = writableVolumeScalarElements()
            for element in channels {
                _ = setFloat(clamped, at: volumeAddress(.scalar(element)))
            }
        }
        return readVolume()
    }

    @discardableResult
    func setMuted(_ muted: Bool) -> Bool {
        guard deviceID != kAudioObjectUnknown else { return false }
        var value: UInt32 = muted ? 1 : 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope:    kAudioDevicePropertyScopeOutput,
            mElement:  kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &value)
        guard status == noErr else { return readMuted() }
        return readMuted()
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
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id
        )
        guard status == noErr else { return kAudioObjectUnknown }
        return id
    }

    private func installListeners() {
        let capturedDeviceID = deviceID
        let capturedOnChange = onChange   // copy the Sendable closure

        // Volume listener
        let volBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            let vol    = self.readVolume()
            let muted  = self.readMuted()
            DispatchQueue.main.async { capturedOnChange(vol, muted) }
        }
        for address in volumeListenerAddresses() {
            addListener(objectID: capturedDeviceID, address: address, block: volBlock)
        }

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
        for registration in volumeListeners {
            var address = registration.address
            AudioObjectRemovePropertyListenerBlock(
                registration.objectID, &address, nil, registration.block
            )
        }
        volumeListeners = []

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

    private enum VolumeAddress {
        case virtualMain
        case scalar(AudioObjectPropertyElement)
    }

    private struct PropertyListenerRegistration {
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private func volumeAddress(_ kind: VolumeAddress) -> AudioObjectPropertyAddress {
        switch kind {
        case .virtualMain:
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope:    kAudioDevicePropertyScopeOutput,
                mElement:  kAudioObjectPropertyElementMain
            )
        case .scalar(let element):
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope:    kAudioDevicePropertyScopeOutput,
                mElement:  element
            )
        }
    }

    private func hasProperty(_ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(deviceID, &address)
    }

    private func isSettable(_ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(deviceID, &address, &settable)
        return status == noErr && settable.boolValue
    }

    private func readFloat(_ address: AudioObjectPropertyAddress) -> Float? {
        var address = address
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return max(0, min(1, value))
    }

    private func setFloat(_ volume: Float, at address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        guard AudioObjectHasProperty(deviceID, &address), isSettable(address) else { return false }
        var value = Float32(max(0, min(1, volume)))
        let size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
        return status == noErr
    }

    private func readableVolumeScalarElements() -> [AudioObjectPropertyElement] {
        preferredStereoChannels().filter { readFloat(volumeAddress(.scalar($0))) != nil }
    }

    private func writableVolumeScalarElements() -> [AudioObjectPropertyElement] {
        preferredStereoChannels().filter {
            isSettable(volumeAddress(.scalar($0))) && readFloat(volumeAddress(.scalar($0))) != nil
        }
    }

    private func preferredStereoChannels() -> [AudioObjectPropertyElement] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope:    kAudioDevicePropertyScopeOutput,
            mElement:  kAudioObjectPropertyElementMain
        )
        var channels = [UInt32](repeating: 0, count: 2)
        var size = UInt32(MemoryLayout<UInt32>.size * channels.count)
        let status = channels.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, buffer.baseAddress!)
        }
        if status == noErr {
            let count = min(Int(size) / MemoryLayout<UInt32>.size, channels.count)
            return (0..<count).map { AudioObjectPropertyElement(channels[$0]) }
        }
        return [1, 2]
    }

    private func volumeListenerAddresses() -> [AudioObjectPropertyAddress] {
        var addresses: [AudioObjectPropertyAddress] = []
        let virtualMain = volumeAddress(.virtualMain)
        if hasProperty(virtualMain) {
            addresses.append(virtualMain)
        }
        for element in preferredStereoChannels() {
            let scalar = volumeAddress(.scalar(element))
            if hasProperty(scalar) {
                addresses.append(scalar)
            }
        }
        return addresses
    }

    private func addListener(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        block: @escaping AudioObjectPropertyListenerBlock
    ) {
        var address = address
        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, nil, block)
        if status == noErr {
            volumeListeners.append(PropertyListenerRegistration(
                objectID: objectID,
                address: address,
                block: block
            ))
        }
    }
}
