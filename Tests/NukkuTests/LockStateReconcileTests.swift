import Testing
@testable import Nukku

/// Pins the level-triggered reconciliation in `LockStateService`: the locked glyph
/// must clear even when the `screenIsUnlocked` distributed notification is never
/// delivered (dropped while the app is suspended across a long system sleep). The
/// injected reader stands in for the window-server session dictionary so the
/// reconcile path can be driven without real notifications or wall-clock sleeps.
@Suite("Lock state reconciliation")
@MainActor
struct LockStateReconcileTests {

    /// Mutable holder so the injected reader can flip mid-test — modelling the OS
    /// session state changing with no notification fired.
    final class LockFlag {
        var locked: Bool
        init(_ locked: Bool) { self.locked = locked }
    }

    @Test("Missed unlock edge is recovered by reconciliation")
    func reconcilesDroppedUnlock() async {
        let flag = LockFlag(true)
        let service = LockStateService(
            reconcileInterval: .milliseconds(20),
            lockStateReader: { flag.locked }
        )
        var unlockCount = 0
        service.onLock = {}
        service.onUnlock = { unlockCount += 1 }

        // The only edge we receive: the lock. Reconciliation starts here.
        service.syncLockState()

        // Authoritative state goes unlocked, but NO notification arrives — exactly
        // the dropped-edge failure. Only the while-locked poll can recover it.
        flag.locked = false

        await waitUntil { unlockCount == 1 }
        #expect(unlockCount == 1)

        service.stop()
    }

    @Test("Reconciliation does not fire unlock while still locked")
    func noPrematureUnlock() async {
        let flag = LockFlag(true)
        let service = LockStateService(
            reconcileInterval: .milliseconds(20),
            lockStateReader: { flag.locked }
        )
        var unlockCount = 0
        service.onLock = {}
        service.onUnlock = { unlockCount += 1 }

        service.syncLockState()                          // committed locked
        try? await Task.sleep(for: .milliseconds(120))   // several reconcile ticks
        #expect(unlockCount == 0)                        // still locked → never unlock

        service.stop()
    }

    /// Polls a condition up to a generous timeout so the assertion is driven by the
    /// real reconcile task completing, not by a fixed guess at how long it takes.
    private func waitUntil(
        _ condition: () -> Bool,
        timeout: Duration = .milliseconds(500)
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
