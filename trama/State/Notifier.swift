import AppKit
import Foundation
import UserNotifications

enum NotificationPreference {
    static let waiting = "notifyWaiting"
    static let done = "notifyDone"

    static func isOn(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    var onOpen: ((_ slug: String, _ path: String) -> Void)?

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func start() {
        guard let center else { return }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func post(_ transition: AgentTransition, tramaTitle: String, path: String) {
        guard let center else { return }
        let key = transition.alert == .waiting ? NotificationPreference.waiting : NotificationPreference.done
        guard NotificationPreference.isOn(key) else { return }
        let agent = transition.agent
        let content = UNMutableNotificationContent()
        content.title = "\(tramaTitle) · \(agent.repo)"
        switch transition.alert {
        case .waiting:
            content.subtitle = "Aguardando você"
            content.body = agent.message.flatMap { $0.isEmpty ? nil : $0 } ?? "O agente pediu sua aprovação."
            content.sound = .default
        case .done:
            content.subtitle = "Agente concluiu"
            content.body = agent.message.flatMap { $0.isEmpty ? nil : $0 } ?? "Sua vez."
        }
        content.userInfo = ["slug": agent.trama, "path": path]
        content.threadIdentifier = agent.trama
        let request = UNNotificationRequest(identifier: "agent-\(agent.session)", content: content, trigger: nil)
        center.add(request)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await MainActor.run { NSApp.isActive } ? [] : [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let slug = info["slug"] as? String, let path = info["path"] as? String else { return }
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            onOpen?(slug, path)
        }
    }
}
