import AppKit
import CoreGraphics

/// Listens for screen lock / unlock via the system's distributed notifications
/// (`com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`) so the notch can
/// surface a lock indicator. The unlock event fires once the user is back on the
/// desktop, so its pill is reliably visible; the lock event fires as the screen
/// secures, so its pill is best-effort only.
@MainActor
final class LockStateService {
    var onLock:   (() -> Void)?
    var onUnlock: (() -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var lastKnownLocked: Bool?

    func start() {
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            observers.append(
                center.addObserver(
                    forName: Notification.Name(name),
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.syncLockState() }
                }
            )
        }
        // Seed from the live session without emitting a spurious transition. A
        // normal (already-unlocked) launch must not fire onUnlock — only a launch
        // *behind* the lock screen should surface the indicator. After seeding, the
        // (unauthenticated) distributed notifications are mere triggers to re-read
        // the authoritative state rather than trusted transitions.
        let locked = Self.isSessionLocked()
        lastKnownLocked = locked
        if locked { onLock?() }
    }

    private func syncLockState() {
        let locked = Self.isSessionLocked()
        guard locked != lastKnownLocked else { return }
        lastKnownLocked = locked
        if locked { onLock?() } else { onUnlock?() }
    }

    /// Reads the live screen-lock state from the window-server session dictionary.
    static func isSessionLocked() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (info["CGSSessionScreenIsLocked"] as? Bool) == true
    }

    func stop() {
        let center = DistributedNotificationCenter.default()
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    isolated deinit {
        stop()
    }
}
