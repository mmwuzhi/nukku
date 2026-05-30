import Foundation
import Observation

@Observable
@MainActor
final class WidgetRegistry {
    static let shared = WidgetRegistry()

    private(set) var widgets: [AnyNukkuWidgetBox] = []

    private init() {}

    // Called once during app startup after all ViewModels exist
    func registerDefaults(
        mediaVM: MediaViewModel,
        systemVM: SystemMonitorViewModel,
        calendarVM: CalendarViewModel,
        fileDropVM: FileDropViewModel
    ) {
        widgets = [
            MediaWidget.box(viewModel: mediaVM),
            ClockWidget.box(),
            SystemMonitorWidget.box(viewModel: systemVM),
            CalendarWidget.box(viewModel: calendarVM),
            FileDropWidget.box(viewModel: fileDropVM)
        ]
    }

    var enabledWidgets: [AnyNukkuWidgetBox] {
        widgets.filter(\.isEnabled)
    }
}
