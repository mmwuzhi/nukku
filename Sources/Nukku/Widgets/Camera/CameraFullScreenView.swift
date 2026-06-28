import SwiftUI

struct CameraFullScreenView: View {
    @Environment(CameraViewModel.self) private var vm

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .ignoresSafeArea()

            CameraPreviewView(previewLayer: vm.previewLayer)
                .ignoresSafeArea()

            Button {
                vm.dismissFullScreen()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.48), in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.18), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help(L10n.tr("camera.closeFullScreen", "退出全屏"))
            .padding(22)
        }
    }
}
