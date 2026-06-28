@preconcurrency import AVFoundation
import CoreMedia
import Observation

@Observable
@MainActor
final class CameraViewModel {
    // nonisolated(unsafe): accessed from background queue for blocking AVFoundation calls.
    // AVCaptureSession is internally thread-safe for configuration/start/stop.
    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated(unsafe) let previewLayer = AVCaptureVideoPreviewLayer()
    private(set) var permissionDenied = false
    private(set) var isRunning = false
    private(set) var isFullScreenPresented = false

    // The camera only runs while the Camera widget is the active Nukku tab. The
    // fullscreen view is just another presentation of that same 720p stream.
    private var wantsWidgetActive = false
    private var isConfigured = false
    private let fullScreenPresenter = CameraFullScreenPresenter()
    nonisolated private let sessionQueue = DispatchQueue(label: "com.nukku.camera.session")

    init() {
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
    }

    func activate() async {
        wantsWidgetActive = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSessionIfNeeded()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard wantsWidgetActive else { return }   // deactivated during the prompt
            if granted { startSessionIfNeeded() } else { permissionDenied = true }
        default:
            permissionDenied = true
        }
    }

    func deactivate() {
        wantsWidgetActive = false
        dismissFullScreen()
        stopSession()
    }

    func toggleFullScreen() {
        if isFullScreenPresented {
            dismissFullScreen()
        } else {
            presentFullScreen()
        }
    }

    func dismissFullScreen() {
        isFullScreenPresented = false
        fullScreenPresenter.dismiss()
    }

    // MARK: - Private

    private func presentFullScreen() {
        guard !permissionDenied, wantsWidgetActive else { return }
        startSessionIfNeeded()
        isFullScreenPresented = true
        fullScreenPresenter.present(viewModel: self) { [weak self] in
            self?.handleFullScreenWindowDismissed()
        }
    }

    private func startSessionIfNeeded() {
        guard wantsWidgetActive else { return }
        if !isConfigured {
            isConfigured = true
            let s = session
            sessionQueue.async {
                Self.configureSession(s)
            }
        }

        guard !isRunning else { return }
        let s = session
        isRunning = true
        sessionQueue.async {
            s.startRunning()
        }
    }

    private func stopSession() {
        guard isRunning else {
            isConfigured = false
            return
        }
        isRunning = false
        isConfigured = false
        let s = session
        sessionQueue.async { s.stopRunning() }
    }

    private func handleFullScreenWindowDismissed() {
        isFullScreenPresented = false
    }

    nonisolated private static func configureSession(_ session: AVCaptureSession) {
        session.beginConfiguration()
        if let device = cameraDevice(in: session) ?? addCameraInput(to: session) {
            setPreset(.high, on: session)
            if !set720pFormatIfAvailable(on: device) {
                setPreset(.high, on: session)
            }
        }
        session.commitConfiguration()
    }

    nonisolated private static func setPreset(_ preset: AVCaptureSession.Preset, on session: AVCaptureSession) {
        if session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }
    }

    nonisolated private static func cameraDevice(in session: AVCaptureSession) -> AVCaptureDevice? {
        session.inputs
            .compactMap { ($0 as? AVCaptureDeviceInput)?.device }
            .first
    }

    nonisolated private static func addCameraInput(to session: AVCaptureSession) -> AVCaptureDevice? {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            return nil
        }
        session.addInput(input)
        return device
    }

    @discardableResult
    nonisolated private static func set720pFormatIfAvailable(on device: AVCaptureDevice) -> Bool {
        let targetWidth: Int32 = 1280
        let targetHeight: Int32 = 720
        guard let format = device.formats
            .map({ (format: $0, dimensions: CMVideoFormatDescriptionGetDimensions($0.formatDescription)) })
            .filter({ $0.dimensions.width >= targetWidth && $0.dimensions.height >= targetHeight })
            .min(by: { lhs, rhs in
                let lhsPixels = Int(lhs.dimensions.width) * Int(lhs.dimensions.height)
                let rhsPixels = Int(rhs.dimensions.width) * Int(rhs.dimensions.height)
                if lhsPixels != rhsPixels { return lhsPixels < rhsPixels }
                let targetAspect = Double(targetWidth) / Double(targetHeight)
                let lhsAspect = abs(Double(lhs.dimensions.width) / Double(lhs.dimensions.height) - targetAspect)
                let rhsAspect = abs(Double(rhs.dimensions.width) / Double(rhs.dimensions.height) - targetAspect)
                return lhsAspect < rhsAspect
            })?.format
        else { return false }

        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            device.unlockForConfiguration()
            return true
        } catch {
            // Fall back to the session preset when exact format selection fails.
            return false
        }
    }
}
