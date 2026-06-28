import AppKit
import CoreGraphics

/// Listens for screen lock / unlock via the system's distributed notifications
/// (`com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`) so the notch can
/// surface a lock indicator. The unlock event fires once the user is back on the
/// desktop, so its pill is reliably visible; the lock event fires as the screen
/// secures, so its pill is best-effort only.
///
/// The distributed notifications are edge triggers only and can be missed — a long
/// system sleep suspends the app across the `screenIsUnlocked` edge, dropping it.
/// Because the locked glyph is intentionally sticky, a single missed unlock would
/// strand it forever (and, with it, suppress the volume HUD). To stay robust the
/// service also reconciles against the authoritative session dictionary from a
/// level-triggered safety net: a low-frequency poll that runs only while locked,
/// plus an immediate re-read on every system / display wake.
@MainActor
final class LockStateService {
    var onLock:   (() -> Void)?
    var onUnlock: (() -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastKnownLocked: Bool?
    private var unlockDebounce: Task<Void, Never>?
    private var lockedReconcile: Task<Void, Never>?

    /// How long the *net* session state must hold "unlocked" before we surface the
    /// unlocked glyph. Clamshell / external-display reconfigure fires lock→unlock
    /// bursts; this swallows them so the indicator settles instead of flapping.
    private static let unlockSettle: Duration = .milliseconds(600)

    /// Interval for the while-locked reconciliation poll. Runs only while locked
    /// (screen off, user away), so a modest cadence is free; it just needs to clear
    /// the glyph promptly after the user returns when an unlock edge was missed.
    private let reconcileInterval: Duration

    /// Authoritative live lock-state read. Injectable so the reconciliation logic
    /// can be exercised deterministically in tests without the real window-server
    /// session dictionary or distributed notifications.
    private let lockStateReader: @MainActor () -> Bool

    init(
        reconcileInterval: Duration = .seconds(2),
        lockStateReader: @escaping @MainActor () -> Bool = { LockStateService.isSessionLocked() }
    ) {
        self.reconcileInterval = reconcileInterval
        self.lockStateReader = lockStateReader
    }

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

        // System / display wake re-reads the authoritative state immediately. After a
        // long sleep the unlock edge may have been dropped while suspended; waking and
        // re-reading converges the glyph to reality without waiting for the next edge.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceObservers.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.syncLockState() }
                }
            )
        }

        // Seed from the live session without emitting a spurious transition. A
        // normal (already-unlocked) launch must not fire onUnlock — only a launch
        // *behind* the lock screen should surface the indicator. After seeding, the
        // (unauthenticated) distributed notifications are mere triggers to re-read
        // the authoritative state rather than trusted transitions.
        let locked = lockStateReader()
        lastKnownLocked = locked
        if locked {
            startLockedReconcile()
            onLock?()
        }
    }

    func syncLockState() {
        let locked = lockStateReader()
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
                guard !Task.isCancelled, let self else { return }
                // Re-read at settle time — the live session dictionary is the
                // authority; a flap that ended back at "locked" must not unlock.
                guard self.lockStateReader() == false else { return }
                self.commit(locked: false)
            }
        }
    }

    /// Apply a settled lock state, emitting at most one transition per real change.
    private func commit(locked: Bool) {
        guard locked != lastKnownLocked else { return }
        lastKnownLocked = locked
        if locked {
            startLockedReconcile()
            onLock?()
        } else {
            stopLockedReconcile()
            onUnlock?()
        }
    }

    /// Level-triggered safety net: while locked, periodically re-read the authoritative
    /// session state and surface the unlock the moment it clears, even if the
    /// `screenIsUnlocked` edge was never delivered (dropped across a long suspension).
    private func startLockedReconcile() {
        lockedReconcile?.cancel()
        let interval = reconcileInterval
        lockedReconcile = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                guard self.lockStateReader() == false else { continue }
                self.commit(locked: false)
                return
            }
        }
    }

    private func stopLockedReconcile() {
        lockedReconcile?.cancel()
        lockedReconcile = nil
    }

    /// Reads the live screen-lock state from the window-server session dictionary.
    static func isSessionLocked() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (info["CGSSessionScreenIsLocked"] as? Bool) == true
    }

    func stop() {
        unlockDebounce?.cancel()
        unlockDebounce = nil
        stopLockedReconcile()
        let center = DistributedNotificationCenter.default()
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspace.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    isolated deinit {
        stop()
    }
}
