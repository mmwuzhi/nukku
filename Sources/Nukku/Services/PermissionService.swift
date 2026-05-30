import Foundation
import EventKit
import AVFoundation

@MainActor
enum PermissionService {
    static func requestCalendarAccess() async -> Bool {
        let store = EKEventStore()
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    static func requestCameraAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}
