import Testing
@testable import Nukku

@Suite("Widget registry")
struct WidgetRegistryTests {
    @Test("Registers correct number of default widgets")
    @MainActor
    func defaultWidgetCount() async {
        let mediaVM    = MediaViewModel()
        let systemVM   = SystemMonitorViewModel()
        let calVM      = CalendarViewModel()
        let fileVM     = FileDropViewModel()
        let registry   = WidgetRegistry.shared
        registry.registerDefaults(
            mediaVM: mediaVM, systemVM: systemVM,
            calendarVM: calVM, fileDropVM: fileVM
        )
        #expect(registry.widgets.count == 5)
    }

    @Test("All default widgets enabled")
    @MainActor
    func allEnabledByDefault() async {
        let mediaVM    = MediaViewModel()
        let systemVM   = SystemMonitorViewModel()
        let calVM      = CalendarViewModel()
        let fileVM     = FileDropViewModel()
        let registry   = WidgetRegistry.shared
        registry.registerDefaults(
            mediaVM: mediaVM, systemVM: systemVM,
            calendarVM: calVM, fileDropVM: fileVM
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

    @Test("targetInteractiveSize matches state")
    @MainActor
    func targetSizeMatchesState() {
        let vm = NotchViewModel()
        #expect(vm.targetInteractiveSize.width == Constants.Notch.collapsedWidth)
        vm.expand()
        #expect(vm.targetInteractiveSize.width == Constants.Notch.expandedWidth)
    }
}
