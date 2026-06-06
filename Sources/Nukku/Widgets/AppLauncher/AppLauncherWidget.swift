import SwiftUI

@MainActor
enum AppLauncherWidget {
    static func box(viewModel: AppLauncherViewModel) -> AnyNukkuWidgetBox {
        makeWidgetBox(
            id: "applauncher",
            displayName: "启动台",
            iconName: "square.grid.2x2",
            accentColor: .indigo,
            preferredSize: CGSize(width: 280, height: 208)
        ) {
            AppLauncherWidgetView()
                .environment(viewModel)
        }
    }
}
