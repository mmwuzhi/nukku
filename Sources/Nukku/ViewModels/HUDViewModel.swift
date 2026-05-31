import Foundation
import Observation

enum HUDType: Equatable {
    case volume(level: Float, muted: Bool)
    case brightness(level: Float)

    var iconName: String {
        switch self {
        case .volume(_, let muted):
            return muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .brightness:
            return "sun.max.fill"
        }
    }

    var level: Float {
        switch self {
        case .volume(let l, _): return l
        case .brightness(let l): return l
        }
    }
}

@Observable
@MainActor
final class HUDViewModel {
    var currentHUD: HUDType? = nil

    private let volumeMonitor  = VolumeMonitor()
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

    // MARK: - Private

    private func show(_ hud: HUDType) {
        currentHUD = hud
        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            currentHUD = nil
        }
    }
}
