import AppKit
import UserNotifications
import BridgeCore

// Never in test mode, and fails quietly if the bundle cannot post notifications.
enum Notify {
    nonisolated(unsafe) static var asked = false

    static func arrived(_ entry: BridgeEntry?) {
        guard let entry, Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        if !asked {
            asked = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = entry.title
        content.body = "Bridge from \(entry.projectName)"
        content.sound = .default
        content.userInfo = ["location": entry.location]
        center.add(UNNotificationRequest(identifier: entry.id, content: content, trigger: nil)) { _ in }
    }

    // A banner for a bridge already opened, crossed or removed points at nothing left to do.
    static func withdraw(_ entry: BridgeEntry?) {
        guard let entry, !Env.test, Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [entry.id])
    }
}
