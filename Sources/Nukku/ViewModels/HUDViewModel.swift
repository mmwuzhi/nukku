import AppKit
import Foundation
import Observation

// NSImage is a reference type and not Sendable, but HUDType is only ever
// created and consumed on @MainActor, so @unchecked Sendable is safe here.
enum HUDType: @unchecked Sendable {
    case volume(level: Float, muted: Bool)
    case brightness(level: Float)
    case battery(level: Float, isCharging: Bool)
    case notification(appName: String, title: String, icon: NSImage?)
    case lock(locked: Bool)

    var iconName: String {
        switch self {
        case .volume(_, let muted): return muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .brightness:           return "sun.max.fill"
        case .battery(let l, let charging):
            if charging { return "bolt.fill" }
            switch l {
            case 0.75...: return "battery.100"
            case 0.50...: return "battery.75"
            case 0.25...: return "battery.50"
            case 0.10...: return "battery.25"
            default:      return "battery.0"
            }
        case .notification: return "bell.fill"
        case .lock(let locked): return locked ? "lock.fill" : "lock.open.fill"
        }
    }

    var level: Float {
        switch self {
        case .volume(let l, _):   return l
        case .brightness(let l):  return l
        case .battery(let l, _):  return l
        case .notification:       return 0
        case .lock:               return 0
        }
    }

    // Percentage label shown next to the progress bar. Shown for volume/brightness/battery
    // so user can see numeric level — for notifications there is none (uses notification layout).
    var percentLabel: String? {
        switch self {
        case .volume(let l, let muted):
            return muted ? "Muted" : "\(Int((l * 100).rounded()))"
        case .brightness(let l):
            return "\(Int((l * 100).rounded()))"
        case .battery(let l, _):
            return "\(Int((l * 100).rounded()))%"
        case .notification:
            return nil
        case .lock:
            return nil
        }
    }

    var dismissDuration: Double {
        switch self {
        case .notification:  return 3.0
        case .lock:          return 2.0
        default:             return 1.5
        }
    }

    var isNotification: Bool {
        if case .notification = self { return true }
        return false
    }

    var isLock: Bool {
        if case .lock = self { return true }
        return false
    }

    var isMuted: Bool {
        if case .volume(_, let muted) = self { return muted }
        return false
    }

    /// Brightness uses the warm accent fill; everything else reads in white.
    var usesAccentFill: Bool {
        if case .brightness = self { return true }
        return false
    }
}

extension HUDType: Equatable {
    static func == (lhs: HUDType, rhs: HUDType) -> Bool {
        switch (lhs, rhs) {
        case (.volume(let l1, let m1), .volume(let l2, let m2)):
            return l1 == l2 && m1 == m2
        case (.brightness(let l1), .brightness(let l2)):
            return l1 == l2
        case (.battery(let l1, let c1), .battery(let l2, let c2)):
            return l1 == l2 && c1 == c2
        case (.notification(let a1, let t1, _), .notification(let a2, let t2, _)):
            return a1 == a2 && t1 == t2
        case (.lock(let l1), .lock(let l2)):
            return l1 == l2
        default:
            return false
        }
    }
}

@Observable
@MainActor
final class HUDViewModel {
    var currentHUD: HUDType? = nil

    /// True between `com.apple.screenIsLocked` and `…Unlocked`. While locked the
    /// notch must not surface notification content above the secure lock screen.
    var isScreenLocked: Bool = false

    private let volumeMonitor     = VolumeMonitor()
    private let volumeKeyInterceptor = VolumeKeyInterceptor()
    private let brightnessMonitor = BrightnessMonitor()
    private let batteryMonitor    = BatteryMonitor()
    private var dismissTask: Task<Void, Never>?

    func start() {
        volumeMonitor.onChange = { [weak self] volume, muted in
            Task { @MainActor [weak self] in
                self?.show(.volume(level: volume, muted: muted))
            }
        }
        brightnessMonitor.onChange = { [weak self] brightness in
            Task { @MainActor [weak self] in
                self?.show(.brightness(level: brightness))
            }
        }
        batteryMonitor.onChange = { [weak self] level, isCharging in
            Task { @MainActor [weak self] in
                self?.show(.battery(level: level, isCharging: isCharging))
            }
        }
        volumeKeyInterceptor.onAction = { [weak self] action in
            Task { @MainActor [weak self] in
                self?.handleVolumeKey(action)
            }
        }
        volumeMonitor.start()
        volumeKeyInterceptor.start(promptForAccessibility: PreferencesManager.shared.replaceSystemVolumeHUD)
        brightnessMonitor.start()
        batteryMonitor.start()
    }

    func stop() {
        volumeKeyInterceptor.stop()
        volumeMonitor.stop()
        brightnessMonitor.stop()
        batteryMonitor.stop()
        dismissTask?.cancel()
        dismissTask = nil
        currentHUD = nil
    }

    // MARK: - Show (internal so NotificationService can call it)

    func show(_ hud: HUDType) {
        // While the secure lock screen is up, only the neutral lock indicator may
        // appear — never media, volume, brightness, or notification content, which
        // would otherwise show through the lock-screen-level SkyLight window.
        if isScreenLocked, !hud.isLock { return }
        // A notification in progress cannot be interrupted by vol/brightness events,
        // but a lock/unlock indicator always wins — it must mask content on lock.
        if let current = currentHUD, current.isNotification, !hud.isNotification, !hud.isLock { return }
        currentHUD = hud
        // The "locked" glyph must persist for the whole locked period; otherwise a
        // dismissal would drop back to .rest and re-expose media art above the lock
        // screen. The "unlocked" glyph dismisses normally back to the live notch.
        if case .lock(true) = hud {
            dismissTask?.cancel()
            dismissTask = nil
        } else {
            scheduleDismiss(duration: hud.dismissDuration)
        }
    }

    // MARK: - Private

    private func scheduleDismiss(duration: Double) {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            currentHUD = nil
        }
    }

    private func handleVolumeKey(_ action: VolumeKeyInterceptor.Action) {
        let step: Float = 1.0 / 16.0

        switch action {
        case .volumeUp:
            if volumeMonitor.readMuted() {
                volumeMonitor.setMuted(false)
            }
            let level = volumeMonitor.setVolume(volumeMonitor.readVolume() + step)
            show(.volume(level: level, muted: false))

        case .volumeDown:
            if volumeMonitor.readMuted() {
                volumeMonitor.setMuted(false)
            }
            let level = volumeMonitor.setVolume(volumeMonitor.readVolume() - step)
            show(.volume(level: level, muted: false))

        case .mute:
            let muted = volumeMonitor.setMuted(!volumeMonitor.readMuted())
            show(.volume(level: volumeMonitor.readVolume(), muted: muted))
        }
    }
}
