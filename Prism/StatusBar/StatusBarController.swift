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
    private var rightClickMonitor: Any?
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
        button.setAccessibilityExpanded(false)
        installRightClickMonitor()
        render()
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        performPresentationAction(presentationState.requestPointerDown(on: .statusItem))
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let presentation = MenuBarLabelRenderer.presentation(
            status: environment.networkViewModel.status,
            mode: environment.settings.menuBarDisplayMode,
            flagStyle: environment.settings.countryFlagStyle,
            customTemplate: environment.settings.customMenuTemplate
        )
        button.title = presentation.title
        switch presentation.indicator {
        case .none:
            button.image = nil
        case .flag(let countryCode):
            button.image = menuBarFlagImage(
                for: countryCode,
                style: environment.settings.countryFlagStyle
            )
        case .emoji(let countryCode):
            button.image = menuBarEmojiImage(for: countryCode)
        case .systemSymbol(let name):
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            image?.isTemplate = true
            image?.size = NSSize(width: 15, height: 15)
            button.image = image
        }
        button.imagePosition = presentation.title.isEmpty ? .imageOnly : .imageLeading

        let status = environment.networkViewModel.status
        if let info = status.info {
            let city = info.location.city.map { " · \($0)" } ?? ""
            let address = info.addresses.preferredForLookup.map { " · \($0)" } ?? ""
            button.toolTip = "\(status.shortLabel) · \(info.location.localizedCountry())\(city)\(address)"
            button.setAccessibilityLabel("\(status.shortLabel), \(info.location.localizedCountry())")
        } else {
            button.toolTip = status.shortLabel
            button.setAccessibilityLabel(status.shortLabel)
        }
    }

    private func menuBarFlagImage(for countryCode: String, style: CountryFlagStyle) -> NSImage? {
        switch style {
        case .cartoon:
            guard let source = CountryFlag.cartoonImage(for: countryCode) else { return nil }
            let size = NSSize(width: 18, height: 18)
            let image = NSImage(size: size, flipped: false) { rect in
                source.draw(
                    in: NSRect(x: 1, y: 3, width: 16, height: 12),
                    from: NSRect(x: 3, y: 15, width: 66, height: 42),
                    operation: .sourceOver,
                    fraction: 1
                )
                return true
            }
            image.isTemplate = false
            return image
        case .waved:
            guard let source = CountryFlag.wavedImage(for: countryCode) else { return nil }
            return fittedMenuBarImage(source)
        case .rounded:
            guard let source = CountryFlag.roundedImage(for: countryCode) else { return nil }
            return fittedMenuBarImage(source)
        case .sticker:
            guard let source = CountryFlag.image(for: countryCode) else { return nil }
            let size = NSSize(width: 18, height: 18)
            let image = NSImage(size: size, flipped: false) { rect in
                NSColor.separatorColor.withAlphaComponent(0.58).setFill()
                NSBezierPath(ovalIn: rect).fill()
                source.draw(
                    in: rect.insetBy(dx: 1, dy: 1),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
                return true
            }
            image.isTemplate = false
            return image
        case .emoji:
            return menuBarEmojiImage(for: countryCode)
        }
    }

    private func fittedMenuBarImage(_ source: NSImage) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = false
        return image
    }

    private func menuBarEmojiImage(for countryCode: String) -> NSImage? {
        guard let emoji = CountryFlag.emoji(for: countryCode) else { return nil }
        let size = NSSize(width: 20, height: 18)
        let attributed = NSAttributedString(
            string: emoji,
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        )
        let textSize = attributed.size()
        return NSImage(size: size, flipped: false) { _ in
            let origin = NSPoint(
                x: Self.pixelAligned((size.width - textSize.width) / 2),
                y: Self.pixelAligned((size.height - textSize.height) / 2)
            )
            attributed.draw(at: origin)
            return true
        }
    }

    private static func pixelAligned(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }

    private func observeChanges() {
        guard !observing else { return }
        observing = true
        withObservationTracking {
            _ = environment.networkViewModel.status
            _ = environment.settings.menuBarDisplayMode
            _ = environment.settings.countryFlagStyle
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
        popoverHost.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
        button.setAccessibilityExpanded(true)
        NSApp.activate(ignoringOtherApps: true)
        popoverHost.popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        statusItem.button?.highlight(false)
        statusItem.button?.setAccessibilityExpanded(false)
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

    private var statusItemScreenFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let frameInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(frameInWindow).insetBy(dx: -4, dy: -4)
    }

    private func isPointerInsideStatusItem(_ event: NSEvent) -> Bool {
        let screenPoint: NSPoint
        if let window = event.window {
            screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        } else {
            screenPoint = event.locationInWindow
        }
        return statusItemScreenFrame?.contains(screenPoint) == true
    }

    private func isStatusItemEvent(_ event: NSEvent) -> Bool {
        guard let statusWindow = statusItem.button?.window, let eventWindow = event.window else {
            return false
        }
        return eventWindow === statusWindow || eventWindow.windowNumber == statusWindow.windowNumber
    }

    private func isPopoverEvent(_ event: NSEvent) -> Bool {
        guard let popoverWindow = popoverHost.popover.contentViewController?.view.window else {
            return false
        }
        return event.window === popoverWindow
    }

    private func installRightClickMonitor() {
        guard rightClickMonitor == nil else { return }
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.isPointerInsideStatusItem(event) else { return false }
                self.requestClosePopover()
                self.showContextMenu()
                return true
            }
            return handled ? nil : event
        }
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let screenPoint = event.locationInWindow
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.statusItemScreenFrame?.contains(screenPoint) == true { return }
                self.requestClosePopover()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let shouldSuppress = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                guard event.window != nil else { return false }
                if event.type == .leftMouseDown,
                   self.isStatusItemEvent(event) || self.isPointerInsideStatusItem(event) {
                    self.requestClosePopover()
                    return true
                }
                guard !self.isPopoverEvent(event) else { return false }
                self.requestClosePopover()
                return false
            }
            return shouldSuppress ? nil : event
        }
    }

    private func removeDismissMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
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
            self.statusItem.button?.setAccessibilityExpanded(false)
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
