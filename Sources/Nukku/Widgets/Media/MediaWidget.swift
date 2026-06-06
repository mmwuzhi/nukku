import SwiftUI

enum MediaWidget {
    @MainActor
    static func box(viewModel: MediaViewModel) -> AnyNukkuWidgetBox {
        makeWidgetBox(
            id: "media",
            displayName: "媒体",
            iconName: "music.note",
            accentColor: .orange,
            preferredSize: CGSize(width: 280, height: 50),
            activate: { Task { await viewModel.refresh() } }
        ) {
            MediaWidgetView()
                .environment(viewModel)
        }
    }
}
