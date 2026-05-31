import SwiftUI

@MainActor
enum CameraWidget {
    static func box(viewModel: CameraViewModel) -> AnyNukkuWidgetBox {
        makeWidgetBox(
            id: "camera",
            displayName: "镜子",
            iconName: "camera.fill"
        ) {
            CameraWidgetView()
                .environment(viewModel)
        } activate: {
            Task { await viewModel.activate() }
        } deactivate: {
            viewModel.deactivate()
        }
    }
}
