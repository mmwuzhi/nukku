import AVFoundation
import Observation

@Observable
@MainActor
final class CameraViewModel {
    // nonisolated(unsafe): accessed from background queue for blocking AVFoundation calls.
    // AVCaptureSession is internally thread-safe for configuration/start/stop.
    nonisolated(unsafe) let session = AVCaptureSession()
    private(set) var permissionDenied = false
    private(set) var isRunning = false

    func activate() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { startSession() } else { permissionDenied = true }
        default:
            permissionDenied = true
        }
    }

    func deactivate() {
        guard isRunning else { return }
        isRunning = false
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
    }

    // MARK: - Private

    private func startSession() {
        guard !isRunning else { return }
        isRunning = true
        let s = session
        DispatchQueue.global(qos: .userInitiated).async {
            // Configure and start on a background thread to avoid blocking @MainActor
            if s.inputs.isEmpty {
                s.sessionPreset = .high
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                                ?? AVCaptureDevice.default(for: .video),
                   let input = try? AVCaptureDeviceInput(device: device),
                   s.canAddInput(input) {
                    s.addInput(input)
                }
            }
            s.startRunning()
        }
    }
}
