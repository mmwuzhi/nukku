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
