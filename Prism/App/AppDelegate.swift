import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()
    private var statusBarController: StatusBarController?
    private var settingsBridgeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        environment.dashboardWindowController = DashboardWindowController(environment: environment)
        statusBarController = StatusBarController(environment: environment)
        installSettingsBridge()
        environment.start()
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            environment.showDashboard()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.stop()
    }

    private func installSettingsBridge() {
        let view = SettingsActionCapture { [weak environment] action in
            environment?.openSettingsAction = { action() }
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: view)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.isExcludedFromWindowsMenu = true
        panel.orderFrontRegardless()
        settingsBridgeWindow = panel
    }
}

private struct SettingsActionCapture: View {
    @Environment(\.openSettings) private var openSettings
    let capture: (OpenSettingsAction) -> Void

    var body: some View {
        Color.clear.frame(width: 1, height: 1).onAppear { capture(openSettings) }
    }
}
