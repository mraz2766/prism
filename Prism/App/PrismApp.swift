import AppIntents
import SwiftUI

@main
struct PrismApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView()
                .environment(appDelegate.environment)
                .environment(appDelegate.environment.settings)
                .environment(appDelegate.environment.settingsViewModel)
                .tint(appDelegate.environment.settings.accentColorChoice.color)
                .accentColor(appDelegate.environment.settings.accentColorChoice.color)
        }
        .commands { AppCommands(environment: appDelegate.environment) }
    }
}
