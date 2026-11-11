import Foundation
import UserNotifications

enum ExitNotificationEvent: Equatable, Sendable {
    case exitChanged(from: NetworkInfo, to: NetworkInfo)
    case fellBackToDomestic(NetworkInfo)
    case overseasRecovered(NetworkInfo)
    case leftExpectedRegion(NetworkInfo, expected: [String])
}

struct ExitNotificationContent: Equatable, Sendable {
    let title: String
    let body: String

    /// `cityName` 用于把英文城市名换成界面一致的本地化名称。
    static func make(
        for event: ExitNotificationEvent,
        locale: Locale = .autoupdatingCurrent,
        cityName: (NetworkInfo) -> String? = { $0.location.city }
    ) -> ExitNotificationContent {
        func place(_ info: NetworkInfo) -> String {
            guard info.hasLocation else { return String(localized: "Country not yet identified") }
            let country = info.location.localizedCountry(locale: locale)
            guard let city = cityName(info), !city.isEmpty else { return country }
            return "\(country) · \(city)"
        }
        func withAddress(_ line: String, _ info: NetworkInfo) -> String {
            guard let address = info.addresses.preferredForLookup else { return line }
            return "\(line)\n\(address)"
        }

        switch event {
        case .exitChanged(let old, let new):
            let oldPlace = place(old)
            let newPlace = place(new)
            let line = oldPlace == newPlace ? newPlace : "\(oldPlace) → \(newPlace)"
            return ExitNotificationContent(
                title: String(localized: "Network exit changed"),
                body: withAddress(line, new)
            )
        case .fellBackToDomestic(let new):
            return ExitNotificationContent(
                title: String(localized: "Overseas exit unreachable"),
                body: withAddress(
                    "\(String(localized: "Now showing the domestic exit")) · \(place(new))",
                    new
                )
            )
        case .overseasRecovered(let new):
            return ExitNotificationContent(
                title: String(localized: "Overseas exit recovered"),
                body: withAddress(place(new), new)
            )
        case .leftExpectedRegion(let new, let expected):
            return ExitNotificationContent(
                title: String(localized: "Exit left the expected region"),
                body: withAddress(
                    "\(place(new)) · \(String(localized: "Expected")) \(expected.joined(separator: ", "))",
                    new
                )
            )
        }
    }
}

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    /// 用户点击通知时打开出口历史。
    var onOpenHistory: (@MainActor () -> Void)?
    private static let threadIdentifier = "com.mraz.prism.exit"

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func notify(
        _ event: ExitNotificationEvent,
        cityName: (NetworkInfo) -> String? = { $0.location.city }
    ) async {
        let rendered = ExitNotificationContent.make(for: event, cityName: cityName)
        let content = UNMutableNotificationContent()
        content.title = rendered.title
        content.body = rendered.body
        content.sound = .default
        content.threadIdentifier = Self.threadIdentifier
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { self.onOpenHistory?() }
    }
}
