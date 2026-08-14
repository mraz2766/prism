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
    case outside
}

struct PopoverDismissHitTester {
    static let hitSlop: CGFloat = 4

    static func target(screenPoint: NSPoint, statusItemFrame: NSRect?) -> PopoverPointerTarget {
        guard let statusItemFrame else { return .outside }
        return statusItemFrame
            .insetBy(dx: -hitSlop, dy: -hitSlop)
            .contains(screenPoint) ? .statusItem : .outside
    }
}

enum PopoverPresentationState: Equatable {
    case closed
    case opening
    case open
    case closing

    mutating func requestToggle() -> PopoverPresentationAction? {
        switch self {
        case .closed:
            self = .opening
            return .open
        case .open:
            self = .closing
            return .close
        case .opening, .closing:
            return nil
        }
    }

    mutating func requestClose() -> PopoverPresentationAction? {
        guard self == .open else { return nil }
        self = .closing
        return .close
    }

    mutating func requestPointerDown(on target: PopoverPointerTarget) -> PopoverPresentationAction? {
        switch target {
        case .statusItem:
            requestToggle()
        case .outside:
            requestClose()
        }
    }

    mutating func didShow() {
        guard self == .opening else { return }
        self = .open
    }

    mutating func willClose() {
        guard self != .closed else { return }
        self = .closing
    }

    mutating func didClose() {
        self = .closed
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
        if NSApp.currentEvent?.type == .rightMouseDown {
            showContextMenu()
        } else {
            switch presentationState.requestPointerDown(on: .statusItem) {
            case .open:
                openPopover()
            case .close:
                closePopover()
            case nil:
                break
            }
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
            presentationState.didClose()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        popoverHost.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popoverHost.popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        removeDismissMonitors()
        popoverHost.popover.performClose(nil)
    }

    private func requestClosePopover() {
        guard presentationState.requestClose() == .close else { return }
        closePopover()
    }

    private var statusItemScreenFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let frameInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(frameInWindow)
    }

    private func requestClosePopover(forPointerAt screenPoint: NSPoint) {
        let target = PopoverDismissHitTester.target(
            screenPoint: screenPoint,
            statusItemFrame: statusItemScreenFrame
        )
        guard target == .outside else { return }
        guard presentationState.requestPointerDown(on: target) == .close else { return }
        closePopover()
    }

    private func requestClosePopoverForApplicationResign() {
        if let event = NSApp.currentEvent,
           event.type == .leftMouseDown || event.type == .rightMouseDown {
            let screenPoint: NSPoint
            if let window = event.window {
                screenPoint = window.convertPoint(toScreen: event.locationInWindow)
            } else {
                screenPoint = event.locationInWindow
            }
            if PopoverDismissHitTester.target(
                screenPoint: screenPoint,
                statusItemFrame: statusItemScreenFrame
            ) == .statusItem {
                return
            }
        }
        requestClosePopover()
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let screenPoint = event.locationInWindow
            Task { @MainActor [weak self] in self?.requestClosePopover(forPointerAt: screenPoint) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                let screenPoint: NSPoint
                if let window = event.window {
                    screenPoint = window.convertPoint(toScreen: event.locationInWindow)
                } else {
                    screenPoint = event.locationInWindow
                }
                self?.requestClosePopover(forPointerAt: screenPoint)
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.presentationState.didShow()
            self.installDismissMonitors()
        }
    }

    nonisolated func popoverWillClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.presentationState.willClose()
            self.removeDismissMonitors()
        }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.presentationState.didClose()
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
