import SwiftUI

@MainActor
enum CameraWidget {
    static func box(viewModel: CameraViewModel) -> AnyNukkuWidgetBox {
        makeWidgetBox(
            id: "camera",
            displayName: "镜子",
            iconName: "camera.fill",
            accentColor: .yellow,
            preferredSize: CGSize(width: 280, height: 170),
            activate: { Task { await viewModel.activate() } },
            deactivate: { viewModel.deactivate() }
        ) {
            CameraWidgetView()
                .environment(viewModel)
        }
    }
}
