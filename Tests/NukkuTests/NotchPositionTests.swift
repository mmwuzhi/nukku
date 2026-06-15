import Testing
@testable import Nukku

@Suite("Widget registry")
struct WidgetRegistryTests {
    @Test("Registers correct number of default widgets")
    @MainActor
    func defaultWidgetCount() async {
        let mediaVM       = MediaViewModel()
        let calVM         = CalendarViewModel()
        let fileVM        = FileDropViewModel()
        let launcherVM    = AppLauncherViewModel()
        let shortcutsVM   = ShortcutsViewModel()
        let cameraVM      = CameraViewModel()
        let registry      = WidgetRegistry.shared
        registry.registerDefaults(
            mediaVM: mediaVM,
            calendarVM: calVM, fileDropVM: fileVM,
            appLauncherVM: launcherVM, shortcutsVM: shortcutsVM,
            cameraVM: cameraVM
        )
        #expect(registry.widgets.count == 6)
    }

    @Test("All default widgets enabled")
    @MainActor
    func allEnabledByDefault() async {
        let mediaVM       = MediaViewModel()
        let calVM         = CalendarViewModel()
        let fileVM        = FileDropViewModel()
        let launcherVM    = AppLauncherViewModel()
        let shortcutsVM   = ShortcutsViewModel()
        let cameraVM      = CameraViewModel()
        let registry      = WidgetRegistry.shared
        registry.registerDefaults(
            mediaVM: mediaVM,
            calendarVM: calVM, fileDropVM: fileVM,
            appLauncherVM: launcherVM, shortcutsVM: shortcutsVM,
            cameraVM: cameraVM
        )
        #expect(registry.enabledWidgets.count == registry.widgets.count)
    }
}

@Suite("NotchViewModel state machine")
struct NotchViewModelTests {
    @Test("Starts collapsed")
    @MainActor
    func startsCollapsed() {
        let vm = NotchViewModel()
        #expect(vm.state == .collapsed)
        #expect(!vm.isExpanded)
    }

    @Test("expand() sets state to expanded")
    @MainActor
    func expandSetsState() {
        let vm = NotchViewModel()
        vm.expand()
        #expect(vm.state == .expanded)
        #expect(vm.isExpanded)
    }

    @Test("targetInteractiveSize reflects fused metrics by state")
    @MainActor
    func targetSizeMatchesState() {
        let vm = NotchViewModel()
        // Rest metrics: topWidth 300, bodyWidth 286 → bounding width 300.
        #expect(vm.targetInteractiveSize.width == max(
            Constants.Geometry.rest.topWidth,
            Constants.Geometry.rest.bodyWidth
        ))
        #expect(vm.targetInteractiveSize.height == Constants.Geometry.rest.height)
        vm.expand()
        // Open metrics: topWidth 318, bodyWidth 300 → bounding width 318.
        #expect(vm.targetInteractiveSize.width == max(
            Constants.Geometry.openBase.topWidth,
            Constants.Geometry.openBase.bodyWidth
        ))
        #expect(vm.targetInteractiveSize.height == Constants.Geometry.openBase.height)

        let hudVM = HUDViewModel()
        vm.hudViewModel = hudVM
        vm.forceCollapse()

        // Volume/brightness/battery read out inside the resting silhouette — no
        // expansion into the wide pill.
        hudVM.show(.volume(level: 0.5, muted: false))
        #expect(vm.presentationMode == .level)
        #expect(vm.targetInteractiveSize.width == max(
            Constants.Geometry.rest.topWidth,
            Constants.Geometry.rest.bodyWidth
        ))
        #expect(vm.targetInteractiveSize.height == Constants.Geometry.rest.height)

        // Notifications still use the wider pill (they need room for text).
        hudVM.show(.notification(appName: "Mail", title: "Hi", icon: nil))
        #expect(vm.presentationMode == .hud)
        #expect(vm.targetInteractiveSize.width == max(
            Constants.Geometry.hud.topWidth,
            Constants.Geometry.hud.bodyWidth
        ))
        #expect(vm.targetInteractiveSize.height == Constants.Geometry.hud.height)

        // The lock indicator also stays inside the resting silhouette.
        hudVM.show(.lock(locked: true))
        #expect(vm.presentationMode == .lock)
        #expect(vm.targetInteractiveSize.height == Constants.Geometry.rest.height)
    }
}
