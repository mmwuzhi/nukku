import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // ViewModels — owned here, injected into window & registry
    let notchVM    = NotchViewModel()
    let mediaVM    = MediaViewModel()
    let systemVM   = SystemMonitorViewModel()
    let calendarVM = CalendarViewModel()
    let fileDropVM = FileDropViewModel()
    let hudVM      = HUDViewModel()

    private var windowManager: NotchWindowManager?
    private var notificationService: NotificationService?
    private let screenService = ScreenChangeService()
    private let launchService = LaunchAtLoginService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Register widgets with shared registry
        WidgetRegistry.shared.registerDefaults(
            mediaVM: mediaVM,
            systemVM: systemVM,
            calendarVM: calendarVM,
            fileDropVM: fileDropVM
        )

        // Start HUD monitoring (volume + brightness) and notification interception
        hudVM.start()
        let ns = NotificationService(hudVM: hudVM)
        notificationService = ns
        Task { await ns.start() }

        // Build and display the notch window
        let mgr = NotchWindowManager(notchViewModel: notchVM, mediaViewModel: mediaVM, hudViewModel: hudVM)
        mgr.setupWindow()
        windowManager = mgr

        // Reposition if screens change
        screenService.onScreenChanged = { [weak mgr] in mgr?.repositionWindow() }

        // Register for launch at login if not already
        if !launchService.isEnabled {
            launchService.enable()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hudVM.stop()
        windowManager?.teardown()
    }
}
