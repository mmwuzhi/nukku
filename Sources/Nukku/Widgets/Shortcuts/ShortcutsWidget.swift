import SwiftUI

@MainActor
enum ShortcutsWidget {
    static func box(viewModel: ShortcutsViewModel) -> AnyNukkuWidgetBox {
        makeWidgetBox(
            id: "shortcuts",
            displayName: "快捷指令",
            iconName: "bolt.fill",
            accentColor: .purple,
            preferredSize: CGSize(width: 280, height: 140)
        ) {
            ShortcutsWidgetView()
                .environment(viewModel)
        }
    }
}
