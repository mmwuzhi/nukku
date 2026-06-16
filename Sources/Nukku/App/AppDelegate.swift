import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // ViewModels — owned here, injected into window & registry
    let notchVM         = NotchViewModel()
    let mediaVM         = MediaViewModel()
    let calendarVM      = CalendarViewModel()
    let fileDropVM      = FileDropViewModel()
    let hudVM           = HUDViewModel()
    let cameraVM        = CameraViewModel()

    private var windowManager: NotchWindowManager?
    private var notificationService: NotificationService?
    private let screenService = ScreenChangeService()
    private let launchService = LaunchAtLoginService()
    private let lockService   = LockStateService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Cross-wire VMs:
        //  - NotchViewModel needs to read HUD state so its `currentMetrics`
        //    resolves to the right fused-shape dimensions for HUD / tap.
        //  - MediaViewModel needs to fire transport-tap HUD pulses.
        notchVM.hudViewModel = hudVM
        mediaVM.hudViewModel = hudVM

        // Start the system now-playing listener (perl-adapter). Done here, not in
        // MediaViewModel.init, so tests can build the VM without spawning a subprocess.
        mediaVM.startSystemNowPlaying()

        // Register widgets with shared registry
        WidgetRegistry.shared.registerDefaults(
            mediaVM:    mediaVM,
            calendarVM: calendarVM,
            fileDropVM: fileDropVM,
            cameraVM:   cameraVM
        )

        // Start HUD monitoring (volume + brightness + battery) and notification interception
        hudVM.start()
        let ns = NotificationService(hudVM: hudVM)
        notificationService = ns
        Task { await ns.start() }

        // Build and display the notch window
        let mgr = NotchWindowManager(notchViewModel: notchVM, mediaViewModel: mediaVM, hudViewModel: hudVM, fileDropViewModel: fileDropVM)
        mgr.setupWindow()
        windowManager = mgr

        // Reposition if screens change
        screenService.onScreenChanged = { [weak mgr] in mgr?.repositionWindow() }

        // Surface a lock/unlock indicator in the notch. On lock, collapse any
        // expanded widget first so calendar/file/camera content is never left
        // above the secure lock screen — only the neutral lock glyph shows.
        lockService.onLock = { [weak notchVM, weak hudVM] in
            hudVM?.isScreenLocked = true
            notchVM?.forceCollapse()
            hudVM?.show(.lock(locked: true))
        }
        lockService.onUnlock = { [weak hudVM] in
            hudVM?.isScreenLocked = false
            hudVM?.show(.lock(locked: false))
        }
        lockService.start()

        // Register for launch at login if not already
        if !launchService.isEnabled {
            launchService.enable()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        lockService.stop()
        hudVM.stop()
        SystemNowPlayingClient.shared.stop()
        windowManager?.teardown()
    }
}
