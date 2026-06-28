import AVFoundation
import SwiftUI
import AppKit

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.setup(session: session)
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {}

    // MARK: - Inner NSView

    final class PreviewNSView: NSView {
        private var previewLayer: AVCaptureVideoPreviewLayer?

        func setup(session: AVCaptureSession) {
            wantsLayer = true
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            self.layer = layer
            previewLayer = layer
            applyMirror()
        }

        override func layout() {
            super.layout()
            previewLayer?.frame = bounds
            applyMirror()
        }

        private func applyMirror() {
            guard let connection = previewLayer?.connection,
                  connection.isVideoMirroringSupported
            else { return }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}
