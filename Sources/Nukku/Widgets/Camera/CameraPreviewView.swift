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

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        nsView.setup(previewLayer: previewLayer)
    }

    static func dismantleNSView(_ nsView: PreviewNSView, coordinator: ()) {
        nsView.teardown()
    }

    // MARK: - Inner NSView

    final class PreviewNSView: NSView {
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var mirrorRefreshTask: Task<Void, Never>?

        deinit {
            mirrorRefreshTask?.cancel()
        }

        func setup(previewLayer: AVCaptureVideoPreviewLayer) {
            wantsLayer = true
            if layer == nil {
                layer = CALayer()
            }
            layer?.backgroundColor = NSColor.black.cgColor
            if self.previewLayer !== previewLayer {
                previewLayer.removeFromSuperlayer()
                layer?.addSublayer(previewLayer)
                self.previewLayer = previewLayer
            }
            layoutPreviewLayerIfOwned()
            refreshMirrorIfOwned()
        }

        func teardown() {
            mirrorRefreshTask?.cancel()
            mirrorRefreshTask = nil
            if ownsPreviewLayer {
                previewLayer?.removeFromSuperlayer()
            }
            previewLayer = nil
        }

        override func layout() {
            super.layout()
            layoutPreviewLayerIfOwned()
            refreshMirrorIfOwned()
        }

        private var ownsPreviewLayer: Bool {
            guard let layer, let previewLayer else { return false }
            return previewLayer.superlayer === layer
        }

        private func layoutPreviewLayerIfOwned() {
            guard ownsPreviewLayer else { return }
            previewLayer?.frame = bounds
        }

        private func refreshMirrorIfOwned() {
            guard ownsPreviewLayer else { return }
            if !applyMirror() {
                scheduleMirrorRefresh()
            }
        }

        @discardableResult
        private func applyMirror() -> Bool {
            guard let connection = previewLayer?.connection,
                  connection.isVideoMirroringSupported
            else { return false }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
            mirrorRefreshTask?.cancel()
            mirrorRefreshTask = nil
            return true
        }

        private func scheduleMirrorRefresh() {
            guard ownsPreviewLayer, mirrorRefreshTask == nil else { return }
            mirrorRefreshTask = Task { @MainActor [weak self] in
                for _ in 0..<8 {
                    guard let self else { return }
                    try? await Task.sleep(for: .milliseconds(60))
                    guard self.ownsPreviewLayer else { return }
                    if self.applyMirror() { return }
                }
                self?.mirrorRefreshTask = nil
            }
        }
    }
}
