import SwiftUI

enum MediaWidget {
    @MainActor
    static func box(viewModel: MediaViewModel) -> AnyNukkuWidgetBox {
        makeWidgetBox(
            id: "media",
            displayName: "媒体",
            iconName: "music.note",
            activate: { Task { await viewModel.refresh() } }
        ) {
            MediaWidgetView()
                .environment(viewModel)
        }
    }
}
