import SwiftUI

enum FileDropWidget {
    @MainActor
    static func box(viewModel: FileDropViewModel) -> AnyNukkuWidgetBox {
        makeWidgetBox(
            id: "filedrop",
            displayName: "文件",
            iconName: "tray",
            accentColor: .blue,
            preferredSize: CGSize(width: 280, height: 100)
        ) {
            FileDropWidgetView()
                .environment(viewModel)
        }
    }
}
