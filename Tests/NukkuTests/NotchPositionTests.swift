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
        let cameraVM      = CameraViewModel()
        let registry      = WidgetRegistry.shared
        registry.registerDefaults(
            mediaVM: mediaVM,
            calendarVM: calVM, fileDropVM: fileVM,
            cameraVM: cameraVM
        )
        #expect(registry.widgets.count == 4)
    }

    @Test("All default widgets enabled")
    @MainActor
    func allEnabledByDefault() async {
        let mediaVM       = MediaViewModel()
        let calVM         = CalendarViewModel()
        let fileVM        = FileDropViewModel()
        let cameraVM      = CameraViewModel()
        let registry      = WidgetRegistry.shared
        registry.registerDefaults(
            mediaVM: mediaVM,
            calendarVM: calVM, fileDropVM: fileVM,
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

    @Test("suppressAutoCollapse blocks the delayed hover-collapse")
    @MainActor
    func suppressBlocksAutoCollapse() async throws {
        let vm = NotchViewModel()
        vm.expand()
        vm.suppressAutoCollapse = true
        vm.collapse()
        // Past the collapse delay the panel must still be expanded: a popover/editor
        // is mid-interaction and must not be torn out from under the cursor.
        try await Task.sleep(for: .seconds(PreferencesManager.shared.collapseDelay + 0.3))
        #expect(vm.state == .expanded)
    }

    @Test("suppression blocks an already scheduled collapse")
    @MainActor
    func suppressionBlocksPendingCollapse() async throws {
        let vm = NotchViewModel()
        vm.expand()
        vm.collapse()
        vm.suppressAutoCollapse = true
        // Opening a modal during the delay must invalidate the pending collapse.
        try await Task.sleep(for: .seconds(PreferencesManager.shared.collapseDelay + 0.3))
        #expect(vm.state == .expanded)
    }

    @Test("collapse can be re-armed after suppression is lifted")
    @MainActor
    func collapseRearmsAfterSuppression() async throws {
        let vm = NotchViewModel()
        vm.expand()
        vm.suppressAutoCollapse = true
        vm.collapse()
        #expect(vm.state == .expanded)

        vm.suppressAutoCollapse = false
        vm.collapse()
        try await Task.sleep(for: .seconds(PreferencesManager.shared.collapseDelay + 0.3))
        #expect(vm.state == .collapsed)
    }

    @Test("forceCollapse() overrides suppression and clears the lock")
    @MainActor
    func forceCollapseOverridesSuppression() {
        let vm = NotchViewModel()
        vm.expand()
        vm.suppressAutoCollapse = true
        vm.forceCollapse()
        #expect(vm.state == .collapsed)
        // The lock must always clear on explicit dismissal so it can't get stuck
        // and leave the notch permanently un-collapsible.
        #expect(vm.suppressAutoCollapse == false)
    }

    @Test("expand() starts with auto-collapse unlocked")
    @MainActor
    func expandResetsSuppression() {
        let vm = NotchViewModel()
        vm.suppressAutoCollapse = true
        vm.expand()
        #expect(vm.suppressAutoCollapse == false)
    }

    @Test("repeated expand preserves suppression for the current session")
    @MainActor
    func repeatedExpandPreservesSuppression() {
        let vm = NotchViewModel()
        vm.expand()
        vm.suppressAutoCollapse = true
        vm.expand()
        #expect(vm.suppressAutoCollapse == true)
    }

    @Test("targetInteractiveSize reflects fused metrics by state")
    @MainActor
    func targetSizeMatchesState() {
        let vm = NotchViewModel()
        // Idle (no media attached) collapses to the bare hardware notch: the
        // resting shoulders carry no content, so the silhouette shrinks to
        // `collapsedWidth` instead of the wider `Geometry.rest` pill.
        #expect(vm.targetInteractiveSize.width == vm.collapsedWidth)
        #expect(vm.targetInteractiveSize.height == vm.collapsedHeight)
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
