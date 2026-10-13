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
    private var lastRendered: RenderedState?
    private var pendingRenderTask: Task<Void, Never>?
    private var imageCache: [String: NSImage] = [:]
    /// 绝大多数候选在 500ms 内确认或撤销；短暂候选不在菜单栏闪烁。
    private let confirmingRevealDelay: Duration = .milliseconds(350)

    private struct RenderedState: Equatable {
        let presentation: MenuBarPresentation
        let flagStyle: CountryFlagStyle
        let appearanceMode: AppearanceMode
        let toolTip: String
        let accessibilityLabel: String
    }

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

    private func scheduleRender() {
        pendingRenderTask?.cancel()
        pendingRenderTask = nil
        let status = environment.networkViewModel.status
        let isCandidate: Bool
        if case .verifying = status { isCandidate = true } else { isCandidate = false }
        guard isCandidate, lastRendered?.presentation.badge == nil else {
            render()
            return
        }
        let delay = confirmingRevealDelay
        pendingRenderTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.pendingRenderTask = nil
            self.render()
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let flagStyle = environment.settings.countryFlagStyle
        let status = environment.networkViewModel.status
        let presentation = MenuBarLabelRenderer.presentation(
            status: status,
            mode: environment.settings.menuBarDisplayMode,
            flagStyle: flagStyle,
            customTemplate: environment.settings.customMenuTemplate
        )

        let toolTip: String
        let accessibilityLabel: String
        if let info = status.info {
            let city = info.location.city.map { " · \($0)" } ?? ""
            let address = info.addresses.preferredForLookup.map { " · \($0)" } ?? ""
            toolTip = "\(status.shortLabel) · \(info.location.localizedCountry())\(city)\(address)"
            accessibilityLabel = "\(status.shortLabel), \(info.location.localizedCountry())"
        } else {
            toolTip = status.shortLabel
            accessibilityLabel = status.shortLabel
        }

        // 时间戳等无关字段变化时不重绘菜单栏。
        let state = RenderedState(
            presentation: presentation,
            flagStyle: flagStyle,
            appearanceMode: environment.settings.appearanceMode,
            toolTip: toolTip,
            accessibilityLabel: accessibilityLabel
        )
        guard state != lastRendered else { return }
        if state.appearanceMode != lastRendered?.appearanceMode {
            imageCache.removeAll()
        }
        lastRendered = state

        button.title = presentation.title
        button.image = indicatorImage(for: presentation, style: flagStyle)
        button.imagePosition = presentation.title.isEmpty ? .imageOnly : .imageLeading
        button.toolTip = toolTip
        button.setAccessibilityLabel(accessibilityLabel)
    }

    private func indicatorImage(for presentation: MenuBarPresentation, style: CountryFlagStyle) -> NSImage? {
        let key: String
        switch presentation.indicator {
        case .none:
            return nil
        case .flag(let countryCode):
            key = "flag/\(style.rawValue)/\(countryCode)/\(presentation.badge?.rawValue ?? "-")"
        case .emoji(let countryCode):
            key = "emoji/\(countryCode)/\(presentation.badge?.rawValue ?? "-")"
        case .systemSymbol(let name):
            key = "symbol/\(name)"
        }
        if let cached = imageCache[key] { return cached }

        let base: NSImage?
        switch presentation.indicator {
        case .none:
            base = nil
        case .flag(let countryCode):
            base = menuBarFlagImage(for: countryCode, style: style)
        case .emoji(let countryCode):
            base = menuBarEmojiImage(for: countryCode)
        case .systemSymbol(let name):
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            image?.isTemplate = true
            image?.size = NSSize(width: 15, height: 15)
            base = image
        }
        guard let base else { return nil }
        let image = presentation.badge.map { badged(base, with: $0) } ?? base

        if imageCache.count >= 48 { imageCache.removeAll(keepingCapacity: true) }
        imageCache[key] = image
        return image
    }

    private func badged(_ base: NSImage, with badge: MenuBarStatusBadge) -> NSImage {
        let size = base.size
        let color: NSColor = switch badge {
        case .confirming: StatusPalette.confirmingNSColor
        case .stale: StatusPalette.staleNSColor
        }
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            let dot = NSRect(x: rect.maxX - 6.5, y: 1, width: 6, height: 6)
            // 先挖出一圈透明描边，让角标在任意壁纸和菜单栏颜色上都清晰。
            if let context = NSGraphicsContext.current {
                context.saveGraphicsState()
                context.compositingOperation = .destinationOut
                NSColor.black.setFill()
                NSBezierPath(ovalIn: dot.insetBy(dx: -1.25, dy: -1.25)).fill()
                context.restoreGraphicsState()
            }
            color.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = false
        return image
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
        case .gradient:
            guard let source = CountryFlag.gradientImage(for: countryCode) else { return nil }
            return roundedMenuBarImage(
                source,
                targetRect: NSRect(x: 0, y: 2.5, width: 18, height: 13),
                cornerRadius: 2.5
            )
        case .rounded:
            guard let source = CountryFlag.roundedImage(for: countryCode, targetWidth: 16) else { return nil }
            return roundedMenuBarImage(
                source,
                targetRect: NSRect(x: 1, y: 3, width: 16, height: 12),
                cornerRadius: 2
            )
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

    private func roundedMenuBarImage(
        _ source: NSImage,
        targetRect: NSRect,
        cornerRadius: CGFloat
    ) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            let clipPath = NSBezierPath(
                roundedRect: targetRect,
                xRadius: cornerRadius,
                yRadius: cornerRadius
            )
            clipPath.addClip()
            source.draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()

            NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
            clipPath.lineWidth = 0.5
            clipPath.stroke()
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
                self.scheduleRender()
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
        if case .online(let info) = environment.networkViewModel.status,
           info.location.city?.isEmpty != false {
            Task { await environment.lookupService.refreshMissingCity() }
        }
        installDismissMonitors()
        popoverHost.popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popoverHost.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
        button.setAccessibilityExpanded(true)
        NSApp.activate()
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
        NSApp.activate()
        environment.openSettingsAction?()
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
