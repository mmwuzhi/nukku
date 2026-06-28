import AVFoundation
import SwiftUI
import AppKit

struct CameraPreviewView: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.setup(previewLayer: previewLayer)
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {}

    // MARK: - Inner NSView

    final class PreviewNSView: NSView {
        private var previewLayer: AVCaptureVideoPreviewLayer?

        func setup(previewLayer: AVCaptureVideoPreviewLayer) {
            wantsLayer = true
            if layer == nil {
                layer = CALayer()
            }
            layer?.backgroundColor = NSColor.black.cgColor
            previewLayer.removeFromSuperlayer()
            layer?.addSublayer(previewLayer)
            self.previewLayer = previewLayer
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
