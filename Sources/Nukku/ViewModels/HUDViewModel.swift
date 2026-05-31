import AppKit
import Foundation
import Observation

// NSImage is a reference type and not Sendable, but HUDType is only ever
// created and consumed on @MainActor, so @unchecked Sendable is safe here.
enum HUDType: @unchecked Sendable {
    case volume(level: Float, muted: Bool)
    case brightness(level: Float)
    case notification(appName: String, title: String, icon: NSImage?)

    var iconName: String {
        switch self {
        case .volume(_, let muted): return muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .brightness:           return "sun.max.fill"
        case .notification:         return "bell.fill"
        }
    }

    var level: Float {
        switch self {
        case .volume(let l, _):  return l
        case .brightness(let l): return l
        case .notification:      return 0
        }
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
        volumeMonitor.start()
        brightnessMonitor.start()
    }

    func stop() {
        volumeMonitor.stop()
        brightnessMonitor.stop()
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
