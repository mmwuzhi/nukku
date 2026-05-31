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
        case .notification:         return "bell.fill"
        }
    }

    var level: Float {
        switch self {
        case .volume(let l, _):   return l
        case .brightness(let l):  return l
        case .battery(let l, _):  return l
        case .notification:       return 0
        }
    }

    // Percentage label shown next to the progress bar (battery only).
    var percentLabel: String? {
        if case .battery(let l, _) = self { return "\(Int(l * 100))%" }
        return nil
    }

    var dismissDuration: Double {
        if case .notification = self { return 3.0 }
        return 1.5
    }

    var isNotification: Bool {
        if case .notification = self { return true }
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
        default:
            return false
        }
    }
}

@Observable
@MainActor
final class HUDViewModel {
    var currentHUD: HUDType? = nil

    private let volumeMonitor     = VolumeMonitor()
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
        volumeMonitor.start()
        brightnessMonitor.start()
        batteryMonitor.start()
    }

    func stop() {
        volumeMonitor.stop()
        brightnessMonitor.stop()
        batteryMonitor.stop()
        dismissTask?.cancel()
        dismissTask = nil
        currentHUD = nil
    }

    // MARK: - Show (internal so NotificationService can call it)

    func show(_ hud: HUDType) {
        // A notification in progress cannot be interrupted by vol/brightness events
        if let current = currentHUD, current.isNotification, !hud.isNotification { return }
        currentHUD = hud
        scheduleDismiss(duration: hud.dismissDuration)
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
}
