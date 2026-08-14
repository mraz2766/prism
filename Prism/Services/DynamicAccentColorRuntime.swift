import AppKit
import ObjectiveC.runtime

final class DynamicAccentColorRuntime: Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var isInstalled = false
    nonisolated(unsafe) private static var _currentChoice: AccentColorChoice = .prismBlue

    static var currentChoice: AccentColorChoice {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _currentChoice
        }
        set {
            lock.lock()
            _currentChoice = newValue
            lock.unlock()
        }
    }

    static var currentNSColor: NSColor {
        currentChoice.nsColor
    }

    static func install() {
        lock.lock()
        defer { lock.unlock() }
        guard !isInstalled else { return }
        isInstalled = true
        swizzleColorMethods()
    }

    @MainActor
    static func apply(choice: AccentColorChoice) {
        currentChoice = choice
        updateAllWindows()
    }

    @MainActor
    private static func updateAllWindows() {
        for window in NSApp.windows {
            window.toolbar?.validateVisibleItems()
            if let toolbar = window.toolbar {
                for item in toolbar.items {
                    if let view = item.view {
                        view.needsDisplay = true
                    }
                }
            }
            window.contentView?.needsDisplay = true
            window.viewsNeedDisplay = true
        }
    }

    private static func swizzleColorMethods() {
        guard let metaClass = object_getClass(NSColor.self) else { return }

        if let original = class_getClassMethod(metaClass, #selector(NSColor.init(named:bundle:))),
           let swizzled = class_getClassMethod(metaClass, #selector(NSColor.prism_colorNamed(_:bundle:))) {
            method_exchangeImplementations(original, swizzled)
        }

        if let original = class_getClassMethod(metaClass, #selector(getter: NSColor.controlAccentColor)),
           let swizzled = class_getClassMethod(metaClass, #selector(NSColor.prism_controlAccentColor)) {
            method_exchangeImplementations(original, swizzled)
        }
    }
}

extension NSColor {
    @objc class func prism_colorNamed(_ name: String, bundle: Bundle?) -> NSColor? {
        if name == "AccentColor" || name == "_controlAccentColor" {
            return DynamicAccentColorRuntime.currentNSColor
        }
        return prism_colorNamed(name, bundle: bundle)
    }

    @objc class func prism_controlAccentColor() -> NSColor {
        return DynamicAccentColorRuntime.currentNSColor
    }
}
