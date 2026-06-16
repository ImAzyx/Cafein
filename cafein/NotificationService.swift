import Foundation
import UserNotifications

/// Abstraction over local notifications so `SleepManager` can be tested without
/// the notification center.
protocol AutoDisableNotifying: AnyObject {
    /// Request authorization lazily (safe to call repeatedly).
    func requestAuthorizationIfNeeded()
    /// Post the "sleep re-enabled" notification (timer-expiry path).
    func notifyAutoDisabled()
}

/// Real implementation backed by `UNUserNotificationCenter`. Local notifications
/// require a signed, bundled app — see the README build instructions.
final class NotificationService: AutoDisableNotifying {
    private let center = UNUserNotificationCenter.current()
    private var didRequest = false

    func requestAuthorizationIfNeeded() {
        guard !didRequest else { return }
        didRequest = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyAutoDisabled() {
        let content = UNMutableNotificationContent()
        content.title = "cafein"
        content.body = "Timer ended — your Mac can sleep again."
        content.sound = .default

        // `trigger: nil` delivers immediately.
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}
