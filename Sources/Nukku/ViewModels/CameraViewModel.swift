import AVFoundation
import CoreMedia
import Observation

@Observable
@MainActor
final class CameraViewModel {
    // nonisolated(unsafe): accessed from background queue for blocking AVFoundation calls.
    // AVCaptureSession is internally thread-safe for configuration/start/stop.
    nonisolated(unsafe) let session = AVCaptureSession()
    private(set) var permissionDenied = false
    private(set) var isRunning = false

    // Tracks whether the widget should be live. Guards the async permission path:
    // if the widget is deactivated (e.g. the screen locks) while the access prompt
    // is up, the post-grant start must be skipped so the camera never runs after
    // deactivation. Serial queue so start/stop can't reorder.
    private var wantsActive = false
    nonisolated private let sessionQueue = DispatchQueue(label: "com.nukku.camera.session")

    func activate() async {
        wantsActive = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard wantsActive else { return }   // deactivated during the prompt
            if granted { startSession() } else { permissionDenied = true }
        default:
            permissionDenied = true
        }
    }

    func deactivate() {
        wantsActive = false
        guard isRunning else { return }
        isRunning = false
        let s = session
        sessionQueue.async { s.stopRunning() }
    }

    // MARK: - Private

    private func startSession() {
        guard wantsActive, !isRunning else { return }
        isRunning = true
        let s = session
        sessionQueue.async {
            // Configure and start on a background thread to avoid blocking @MainActor
            if s.inputs.isEmpty {
                s.beginConfiguration()
                s.sessionPreset = .high
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                                ?? AVCaptureDevice.default(for: .video),
                   let input = try? AVCaptureDeviceInput(device: device),
                   s.canAddInput(input) {
                    s.addInput(input)
                    Self.enableCenterStageIfSupported(on: device)
                }
                s.commitConfiguration()
            }
            s.startRunning()
        }
    }

    /// Opt into Center Stage (auto-framing) when the camera supports it, the way
    /// FaceTime does: `.cooperative` lets both the user (Control Center) and the
    /// app toggle it, and we default it on. No-op on cameras without a
    /// Center-Stage-capable format (many built-in MacBook cameras), where the
    /// feed stays normal. Must run inside the session's begin/commitConfiguration.
    nonisolated private static func enableCenterStageIfSupported(on device: AVCaptureDevice) {
        guard device.formats.contains(where: { $0.isCenterStageSupported }) else { return }
        AVCaptureDevice.centerStageControlMode = .cooperative
        do {
            try device.lockForConfiguration()
            // Center Stage can only be enabled on a supporting format; switch to the
            // highest-resolution supported one if the current format doesn't qualify.
            if !device.activeFormat.isCenterStageSupported,
               let best = device.formats
                   .filter({ $0.isCenterStageSupported })
                   .max(by: { pixelCount($0) < pixelCount($1) }) {
                device.activeFormat = best
            }
            AVCaptureDevice.isCenterStageEnabled = true
            device.unlockForConfiguration()
        } catch {
            // Leave the normal feed if the device can't be locked for configuration.
        }
    }

    nonisolated private static func pixelCount(_ format: AVCaptureDevice.Format) -> Int {
        let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return Int(d.width) * Int(d.height)
    }
}
