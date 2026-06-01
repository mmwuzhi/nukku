import AppKit
import Foundation
import UserNotifications

/// Registers Nukku as the UNUserNotificationCenter delegate so notifications
/// delivered to this process are shown in the notch HUD instead of a system banner.
///
/// Scope: only notifications sent to Nukku's own process (e.g. calendar reminders
/// from EventKit). Cross-app interception requires Accessibility access and is a
/// future extension.
@MainActor
final class NotificationService: NSObject {

    private weak var hudVM: HUDViewModel?

    init(hudVM: HUDViewModel) {
        self.hudVM = hudVM
        super.init()
    }

    func start() async {
        guard await PermissionService.requestNotificationAccess() else { return }
        UNUserNotificationCenter.current().delegate = self
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {

    // Called when a notification arrives while the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let contentTitle = notification.request.content.title
        let contentSubtitle = notification.request.content.subtitle
        Task { @MainActor [weak self] in
            guard let self, let hudVM = self.hudVM else { return }
            let appName  = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
                           ?? Bundle.main.bundleIdentifier
                           ?? "Nukku"
            let rawTitle = contentTitle.isEmpty ? contentSubtitle : contentTitle
            let title    = String(rawTitle.prefix(120))
                           .trimmingCharacters(in: .controlCharacters)
            let icon     = NSApp.applicationIconImage
            hudVM.show(.notification(
                appName: appName,
                title:   title.isEmpty ? appName : title,
                icon:    icon
            ))
        }
        // Suppress the system banner — the notch HUD is our replacement
        completionHandler([])
    }
}
