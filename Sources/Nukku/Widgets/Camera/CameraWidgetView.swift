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
        CameraPreviewView(session: vm.session)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.3))
            Text("摄像头权限已拒绝")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Button("在系统设置中开启") {
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
