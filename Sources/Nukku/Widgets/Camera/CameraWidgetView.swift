import AppKit
import SwiftUI

struct CameraWidgetView: View {
    @Environment(CameraViewModel.self) private var vm

    var body: some View {
        if vm.permissionDenied {
            permissionDeniedView
        } else {
            cameraPreview
        }
    }

    private var cameraPreview: some View {
        ZStack(alignment: .topTrailing) {
            if vm.isFullScreenPresented {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black)
                    .overlay {
                        Image(systemName: "rectangle.inset.filled.and.person.filled")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.42))
                    }
            } else {
                CameraPreviewView(previewLayer: vm.previewLayer)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                vm.toggleFullScreen()
            } label: {
                Image(systemName: vm.isFullScreenPresented ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(.black.opacity(0.46), in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.20), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .help(vm.isFullScreenPresented
                  ? L10n.tr("camera.exitFullScreen", "退出全屏")
                  : L10n.tr("camera.fullScreen", "全屏显示"))
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.55))
            Text(L10n.tr("camera.permissionDenied", "摄像头权限已拒绝"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Button(L10n.tr("camera.openSystemSettings", "在系统设置中开启")) {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
                )
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.blue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
