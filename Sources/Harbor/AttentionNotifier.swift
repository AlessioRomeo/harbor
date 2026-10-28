import AppKit
import os
import UserNotifications

/// Tells me about sessions that need me when I'm not looking: the Dock badge and a notification.
final class AttentionNotifier: NSObject, UNUserNotificationCenterDelegate {
    nonisolated private static let logger = Logger(subsystem: "com.alessioromeo.harbor", category: "notifications")
    nonisolated private static let sessionKey = "sessionID"

    var onOpen: ((UUID) -> Void)?

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Self.logger.error("Notification permission failed: \(String(describing: error))")
            } else if !granted {
                Self.logger.info("Notifications are off for Harbor; the Dock badge still shows")
            }
        }
    }

    func setBadge(_ count: Int) {
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    func notify(sessionID: UUID, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [Self.sessionKey: sessionID.uuidString]
        let request = UNNotificationRequest(identifier: sessionID.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.logger.error("Could not post a notification: \(String(describing: error))")
            }
        }
    }

    func withdraw(sessionID: UUID) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [sessionID.uuidString])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let text = response.notification.request.content.userInfo[Self.sessionKey] as? String,
              let id = UUID(uuidString: text) else { return }
        await MainActor.run {
            NSApp.activate()
            onOpen?(id)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Calls back when files in a directory are added, replaced or removed.
final class DirectoryWatcher {
    private let source: DispatchSourceFileSystemObject

    init?(url: URL, onChange: @escaping () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
