import AppKit
import SwiftUI

@MainActor
final class DashboardWindowController: NSWindowController, NSWindowDelegate {
    init(environment: AppEnvironment) {
        let rootView = DashboardRootView()
            .environment(environment)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Prism"
        window.minSize = NSSize(width: 640, height: 460)
        window.center()
        // Keep screenshot-based UI tests on the primary display even when another screen is active.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"), let screen = NSScreen.screens.first {
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: visible.midX - window.frame.width / 2,
                y: visible.midY - window.frame.height / 2
            ))
        }
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: rootView)
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func showWindow() {
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.orderOut(nil)
    }
}
