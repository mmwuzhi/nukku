import SwiftUI

enum SystemMonitorWidget {
    @MainActor
    static func box(viewModel: SystemMonitorViewModel) -> AnyNukkuWidgetBox {
        makeWidgetBox(
            id: "system",
            displayName: "系统",
            iconName: "cpu",
            activate: { viewModel.start() },
            deactivate: { viewModel.stop() }
        ) {
            SystemMonitorView()
                .environment(viewModel)
        }
    }
}
