import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // ViewModels — owned here, injected into window & registry
    let notchVM = NotchViewModel()
    let mediaVM = MediaViewModel()
    let systemVM = SystemMonitorViewModel()
    let calendarVM = CalendarViewModel()
    let fileDropVM = FileDropViewModel()

    private var windowManager: NotchWindowManager?
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

        // Build and display the notch window
        let mgr = NotchWindowManager(notchViewModel: notchVM, mediaViewModel: mediaVM)
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
        windowManager?.teardown()
    }
}
