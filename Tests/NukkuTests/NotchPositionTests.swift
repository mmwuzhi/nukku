import Testing
import AppKit
@testable import Nukku

@Suite("Notch position helpers")
struct NotchPositionTests {
    @Test("WidgetRegistry registers correct number of default widgets")
    @MainActor
    func defaultWidgetCount() async {
        let mediaVM = MediaViewModel()
        let systemVM = SystemMonitorViewModel()
        let calVM = CalendarViewModel()
        let fileVM = FileDropViewModel()
        let registry = WidgetRegistry.shared
        registry.registerDefaults(mediaVM: mediaVM, systemVM: systemVM, calendarVM: calVM, fileDropVM: fileVM)
        #expect(registry.widgets.count == 5)
    }

    @Test("All default widgets are enabled by default")
    @MainActor
    func allWidgetsEnabledByDefault() async {
        let mediaVM = MediaViewModel()
        let systemVM = SystemMonitorViewModel()
        let calVM = CalendarViewModel()
        let fileVM = FileDropViewModel()
        let registry = WidgetRegistry.shared
        registry.registerDefaults(mediaVM: mediaVM, systemVM: systemVM, calendarVM: calVM, fileDropVM: fileVM)
        #expect(registry.enabledWidgets.count == registry.widgets.count)
    }
}
