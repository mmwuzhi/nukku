import AppKit

@MainActor
final class ScreenChangeService {
    private var observer: NSObjectProtocol?
    var onScreenChanged: (() -> Void)?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onScreenChanged?()
            }
        }
    }

    isolated deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
