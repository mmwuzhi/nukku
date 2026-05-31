import SwiftUI

@MainActor
enum ShortcutsWidget {
    static func box(viewModel: ShortcutsViewModel) -> AnyNukkuWidgetBox {
        makeWidgetBox(
            id: "shortcuts",
            displayName: "快捷指令",
            iconName: "bolt.fill"
        ) {
            ShortcutsWidgetView()
                .environment(viewModel)
        }
    }
}
