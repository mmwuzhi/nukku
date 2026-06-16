import SwiftUI

enum CalendarWidget {
    @MainActor
    static func box(viewModel: CalendarViewModel) -> AnyNukkuWidgetBox {
        makeWidgetBox(
            id: "calendar",
            displayName: "日历",
            iconName: "calendar",
            accentColor: .red,
            preferredSize: CGSize(width: 280, height: 236),
            activate: { Task { await viewModel.activate() } },
            deactivate: { viewModel.deactivate() }
        ) {
            CalendarWidgetView()
                .environment(viewModel)
        }
    }
}
