import Observation

@MainActor
@Observable
final class SettingsViewModel {
    let settings: SettingsStore
    private let launchAtLoginService: LaunchAtLoginService
    private let notificationService: NotificationService
    private(set) var launchAtLoginError: String?

    init(
        settings: SettingsStore,
        launchAtLoginService: LaunchAtLoginService,
        notificationService: NotificationService
    ) {
        self.settings = settings
        self.launchAtLoginService = launchAtLoginService
        self.notificationService = notificationService
    }

    func synchronizeLaunchAtLogin() {
        settings.launchAtLogin = launchAtLoginService.isEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginService.setEnabled(enabled)
            settings.launchAtLogin = enabled
            launchAtLoginError = nil
        } catch {
            settings.launchAtLogin = launchAtLoginService.isEnabled
            launchAtLoginError = error.localizedDescription
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        if enabled {
            settings.changeNotificationsEnabled = await notificationService.requestAuthorization()
        } else {
            settings.changeNotificationsEnabled = false
        }
    }

    /// 守护提醒依赖系统通知；用户拒绝授权时仍可启用，界面与菜单栏标记照常生效。
    func setRegionGuardEnabled(_ enabled: Bool) async {
        settings.regionGuardEnabled = enabled
        if enabled { _ = await notificationService.requestAuthorization() }
    }
}
