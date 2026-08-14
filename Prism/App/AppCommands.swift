import SwiftUI

struct AppCommands: Commands {
    let environment: AppEnvironment

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(String(localized: "Open Details")) {
                environment.showDashboard()
            }
            .keyboardShortcut("o", modifiers: [.command])
        }
        CommandGroup(replacing: .saveItem) {
            Button(String(localized: "Refresh")) {
                environment.refreshCoordinator.triggerManual()
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
    }
}
