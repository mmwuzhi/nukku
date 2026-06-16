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
        calendarVM: CalendarViewModel,
        fileDropVM: FileDropViewModel,
        cameraVM: CameraViewModel
    ) {
        widgets = [
            MediaWidget.box(viewModel: mediaVM),
            CalendarWidget.box(viewModel: calendarVM),
            FileDropWidget.box(viewModel: fileDropVM),
            CameraWidget.box(viewModel: cameraVM)
        ]
    }

    var enabledWidgets: [AnyNukkuWidgetBox] {
        widgets.filter(\.isEnabled)
    }

    func nextEnabledID(after id: String?) -> String? {
        let enabled = enabledWidgets
        guard !enabled.isEmpty else { return nil }
        guard let id, let idx = enabled.firstIndex(where: { $0.id == id }) else {
            return enabled.first?.id
        }
        return enabled[(idx + 1) % enabled.count].id
    }

    func prevEnabledID(before id: String?) -> String? {
        let enabled = enabledWidgets
        guard !enabled.isEmpty else { return nil }
        guard let id, let idx = enabled.firstIndex(where: { $0.id == id }) else {
            return enabled.last?.id
        }
        return enabled[(idx - 1 + enabled.count) % enabled.count].id
    }
}
