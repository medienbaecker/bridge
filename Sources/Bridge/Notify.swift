import AppKit
import UserNotifications
import BridgeCore

// Never in test mode, and fails quietly if the bundle cannot post notifications.
enum Notify {
    nonisolated(unsafe) static var asked = false

    static func arrived(_ entry: BridgeEntry?) {
        guard let entry else { return }
        post(entry, body: "Bridge from \(entry.projectName)", sound: Settings.arrivalSound)
    }

    static func updated(_ entry: BridgeEntry?) {
        guard let entry, Settings.updateNotices else { return }
        post(entry, body: "Updated · \(entry.projectName)", sound: false)
    }

    static func denied() async -> Bool {
        if Env.test { return ProcessInfo.processInfo.environment["BRIDGE_NOTIFICATIONS"] == "denied" }
        guard Bundle.main.bundleIdentifier != nil else { return false }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    static func openSystemSettings() {
        guard let id = Bundle.main.bundleIdentifier, let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") else { return }
        NSWorkspace.shared.open(url)
    }

    static func post(_ entry: BridgeEntry, body: String, sound: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        if !asked {
            asked = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = entry.title
        content.body = body
        if sound { content.sound = .default }
        content.userInfo = ["location": entry.location]
        center.add(UNNotificationRequest(identifier: entry.id, content: content, trigger: nil)) { _ in }
    }

    // A banner for a bridge already opened, crossed or removed points at nothing left to do.
    static func withdraw(_ entry: BridgeEntry?) {
        guard let entry, !Env.test, Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [entry.id])
    }
}
