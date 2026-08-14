import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func notifyExitChange(from old: NetworkInfo, to new: NetworkInfo) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Network exit changed")
        if old.location.countryCode != new.location.countryCode {
            let oldCountry = old.location.localizedCountry()
            let newCountry = new.location.localizedCountry()
            content.body = "\(oldCountry) → \(newCountry)"
        } else {
            content.body = String(localized: "Your public network exit has changed")
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
