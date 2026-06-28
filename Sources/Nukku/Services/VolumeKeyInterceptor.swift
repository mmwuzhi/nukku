@preconcurrency import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

/// Intercepts hardware volume keys before macOS shows its own HUD.
///
/// Returning nil from the event tap suppresses the original system-defined key
/// event, so the caller must perform the actual volume change itself.
final class VolumeKeyInterceptor: @unchecked Sendable {
    enum Action: Sendable {
        case volumeUp
        case volumeDown
        case mute
    }

    var onAction: @Sendable (Action) -> Void = { _ in }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start(promptForAccessibility: Bool) {
        stop()

        guard accessibilityTrusted(prompt: promptForAccessibility) else { return }

        let mask = CGEventMask(1 << nxEventTypeSystemDefined)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: volumeKeyEventTapCallback,
            userInfo: refcon
        ) else {
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    fileprivate func handle(_ event: CGEvent) -> Bool {
        guard UserDefaults.standard.object(forKey: "replaceSystemVolumeHUD") as? Bool ?? true else {
            return false
        }
        guard let action = Self.action(from: event) else { return false }
        onAction(action)
        return true
    }

    fileprivate func reenableTapIfNeeded() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func accessibilityTrusted(prompt: Bool) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func action(from event: CGEvent) -> Action? {
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == nxSubtypeAuxControlButtons
        else {
            return nil
        }

        let data = nsEvent.data1
        let keyCode = Int((data & 0xFFFF0000) >> 16)
        let keyState = Int((data & 0x0000FF00) >> 8)
        guard keyState == nxKeyStateDown else { return nil }

        switch keyCode {
        case nxKeyTypeSoundUp:
            return .volumeUp
        case nxKeyTypeSoundDown:
            return .volumeDown
        case nxKeyTypeMute:
            return .mute
        default:
            return nil
        }
    }
}

private let nxSubtypeAuxControlButtons = 8
private let nxEventTypeSystemDefined: UInt32 = 14
private let nxKeyStateDown = 0x0A
private let nxKeyTypeSoundUp = 0
private let nxKeyTypeSoundDown = 1
private let nxKeyTypeMute = 7

private let volumeKeyEventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else {
        return Unmanaged.passUnretained(event)
    }

    let interceptor = Unmanaged<VolumeKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        interceptor.reenableTapIfNeeded()
        return Unmanaged.passUnretained(event)
    }

    guard type.rawValue == nxEventTypeSystemDefined else {
        return Unmanaged.passUnretained(event)
    }

    if interceptor.handle(event) {
        return nil
    }
    return Unmanaged.passUnretained(event)
}
