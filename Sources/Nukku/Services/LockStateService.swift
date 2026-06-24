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
    private var unlockDebounce: Task<Void, Never>?

    /// How long the *net* session state must hold "unlocked" before we surface the
    /// unlocked glyph. Clamshell / external-display reconfigure fires lock→unlock
    /// bursts; this swallows them so the indicator settles instead of flapping.
    private static let unlockSettle: Duration = .milliseconds(600)

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
        if locked {
            // Lock must take effect immediately — never debounced — so no widget /
            // media content is ever left visible above the secure lock screen. A
            // pending unlock is stale the moment we read "locked", so drop it.
            unlockDebounce?.cancel()
            unlockDebounce = nil
            commit(locked: true)
        } else {
            // Unlock is debounced. The unauthenticated screenIsLocked/Unlocked
            // distributed notifications fire in rapid lock→unlock→lock bursts when
            // displays reconfigure (clamshell, external monitor). Emitting on every
            // edge re-shows the unlocked glyph and re-arms its 2s dismiss timer, so
            // the open padlock never clears. Wait for the live state to settle on
            // "unlocked" before surfacing the transition.
            unlockDebounce?.cancel()
            unlockDebounce = Task { [weak self] in
                try? await Task.sleep(for: Self.unlockSettle)
                guard !Task.isCancelled else { return }
                // Re-read at settle time — the live session dictionary is the
                // authority; a flap that ended back at "locked" must not unlock.
                guard Self.isSessionLocked() == false else { return }
                self?.commit(locked: false)
            }
        }
    }

    /// Apply a settled lock state, emitting at most one transition per real change.
    private func commit(locked: Bool) {
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
        unlockDebounce?.cancel()
        unlockDebounce = nil
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
