import AppKit
import Observation

extension Notification.Name {
    static let prismClosePopover = Notification.Name("com.mraz.prism.closePopover")
}

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let environment: AppEnvironment
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popoverHost: PopoverHost
    private var anchorWindow: NSWindow?
    private var globalMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?
    private var observing = false

    init(environment: AppEnvironment) {
        self.environment = environment
        popoverHost = PopoverHost(environment: environment)
        super.init()
        popoverHost.popover.delegate = self
        configureButton()
        observeChanges()
        closeObserver = NotificationCenter.default.addObserver(
            forName: .prismClosePopover,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.closePopover() }
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        statusItem.autosaveName = "com.mraz.prism.statusItem"
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        render()
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else if popoverHost.popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    private func render() {
        statusItem.button?.title = MenuBarLabelRenderer.render(
            status: environment.networkViewModel.status,
            mode: environment.settings.menuBarDisplayMode,
            customTemplate: environment.settings.customMenuTemplate
        )
        let status = environment.networkViewModel.status
        if let info = status.info {
            let city = info.location.city.map { " · \($0)" } ?? ""
            let address = info.addresses.preferredForLookup.map { " · \($0)" } ?? ""
            statusItem.button?.toolTip = "\(status.shortLabel) · \(info.location.localizedCountry())\(city)\(address)"
        } else {
            statusItem.button?.toolTip = status.shortLabel
        }
    }

    private func observeChanges() {
        guard !observing else { return }
        observing = true
        withObservationTracking {
            _ = environment.networkViewModel.status
            _ = environment.settings.menuBarDisplayMode
            _ = environment.settings.customMenuTemplate
            _ = environment.settings.appearanceMode
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observing = false
                self.render()
                self.observeChanges()
            }
        }
    }

    private func openPopover() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        let frame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let anchor = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        anchor.isOpaque = false
        anchor.backgroundColor = .clear
        anchor.ignoresMouseEvents = true
        anchor.level = .statusBar
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        anchor.contentView = view
        anchor.orderFrontRegardless()
        anchorWindow = anchor
        popoverHost.popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        popoverHost.popover.contentViewController?.view.window?.makeKey()
        installDismissMonitors()
    }

    private func closePopover() {
        removeDismissMonitors()
        popoverHost.popover.performClose(nil)
        anchorWindow?.orderOut(nil)
        anchorWindow = nil
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.closePopover() }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.closePopover() }
        }
    }

    private func removeDismissMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.removeDismissMonitors()
            self?.anchorWindow?.orderOut(nil)
            self?.anchorWindow = nil
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(item(title: String(localized: "Refresh"), action: #selector(refresh), key: "r"))
        menu.addItem(item(title: String(localized: "Open Details"), action: #selector(openDetails), key: "o"))
        menu.addItem(.separator())
        menu.addItem(item(title: String(localized: "Settings…"), action: #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item(title: String(localized: "Quit Prism"), action: #selector(quit), key: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func refresh() { environment.refreshCoordinator.triggerManual() }
    @objc private func openDetails() { environment.showDashboard() }
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        environment.openSettingsAction?()
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
