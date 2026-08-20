import AppKit
import Observation

extension Notification.Name {
    static let prismClosePopover = Notification.Name("com.mraz.prism.closePopover")
}

enum PopoverPresentationAction: Equatable {
    case open
    case close
}

enum PopoverPointerTarget: Equatable {
    case statusItem
    case popover
    case outside
}

struct PopoverPresentationState: Equatable {
    private(set) var isPresented = false

    static let closed = PopoverPresentationState()

    mutating func requestToggle() -> PopoverPresentationAction {
        isPresented.toggle()
        return isPresented ? .open : .close
    }

    mutating func requestClose() -> PopoverPresentationAction? {
        guard isPresented else { return nil }
        isPresented = false
        return .close
    }

    mutating func requestPointerDown(on target: PopoverPointerTarget) -> PopoverPresentationAction? {
        switch target {
        case .statusItem:
            requestToggle()
        case .outside:
            requestClose()
        case .popover:
            nil
        }
    }

    mutating func didClose() {
        isPresented = false
    }
}

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let environment: AppEnvironment
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popoverHost: PopoverHost
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?
    private var observing = false
    private var presentationState = PopoverPresentationState.closed

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
            Task { @MainActor [weak self] in self?.requestClosePopover() }
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        statusItem.autosaveName = "com.mraz.prism.statusItem"
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        render()
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseDown {
            requestClosePopover()
            showContextMenu()
        } else {
            performPresentationAction(presentationState.requestPointerDown(on: .statusItem))
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
        guard let button = statusItem.button else {
            _ = presentationState.requestClose()
            presentationState.didClose()
            return
        }
        installDismissMonitors()
        NSApp.activate(ignoringOtherApps: true)
        popoverHost.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popoverHost.popover.contentViewController?.view.window?.makeKey()
        button.highlight(true)
    }

    private func closePopover() {
        statusItem.button?.highlight(false)
        removeDismissMonitors()
        if popoverHost.popover.isShown {
            popoverHost.popover.performClose(nil)
        } else {
            presentationState.didClose()
        }
    }

    private func performPresentationAction(_ action: PopoverPresentationAction?) {
        switch action {
        case .open:
            openPopover()
        case .close:
            closePopover()
        case nil:
            break
        }
    }

    private func requestClosePopover() {
        performPresentationAction(presentationState.requestClose())
    }

    private func requestClosePopoverForApplicationResign() {
        requestClosePopover()
    }

    private func isStatusItemEvent(_ event: NSEvent) -> Bool {
        guard let statusWindow = statusItem.button?.window else { return false }
        return event.window === statusWindow
    }

    private func isPopoverEvent(_ event: NSEvent) -> Bool {
        guard let popoverWindow = popoverHost.popover.contentViewController?.view.window else {
            return false
        }
        return event.window === popoverWindow
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.requestClosePopover() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard event.window != nil else { return }
                guard !self.isStatusItemEvent(event), !self.isPopoverEvent(event) else { return }
                self.requestClosePopover()
            }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.requestClosePopoverForApplicationResign() }
        }
    }

    private func removeDismissMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
    }

    nonisolated func popoverDidShow(_ notification: Notification) {
        MainActor.assumeIsolated { [weak self] in
            self?.statusItem.button?.highlight(true)
        }
    }

    nonisolated func popoverWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { [weak self] in
            self?.removeDismissMonitors()
        }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated { [weak self] in
            guard let self else { return }
            guard !self.popoverHost.popover.isShown else { return }
            self.presentationState.didClose()
            self.statusItem.button?.highlight(false)
            self.removeDismissMonitors()
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
