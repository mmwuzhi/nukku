import SwiftUI

enum FileDropWidget {
    @MainActor
    static func box(viewModel: FileDropViewModel) -> AnyNukkuWidgetBox {
        makeWidgetBox(
            id: "filedrop",
            displayName: "文件",
            iconName: "tray"
        ) {
            FileDropWidgetView()
                .environment(viewModel)
        }
    }
}
