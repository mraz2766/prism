import AppKit
import Carbon.HIToolbox

enum GlobalHotKeyChoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case off
    case optionCommandP
    case controlOptionP
    case controlOptionCommandP
    case controlShiftSpace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: String(localized: "Off")
        case .optionCommandP: "⌥⌘P"
        case .controlOptionP: "⌃⌥P"
        case .controlOptionCommandP: "⌃⌥⌘P"
        case .controlShiftSpace: "⌃⇧Space"
        }
    }

    var keyCode: UInt32? {
        switch self {
        case .off: nil
        case .optionCommandP, .controlOptionP, .controlOptionCommandP: UInt32(kVK_ANSI_P)
        case .controlShiftSpace: UInt32(kVK_Space)
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .off: 0
        case .optionCommandP: UInt32(optionKey | cmdKey)
        case .controlOptionP: UInt32(controlKey | optionKey)
        case .controlOptionCommandP: UInt32(controlKey | optionKey | cmdKey)
        case .controlShiftSpace: UInt32(controlKey | shiftKey)
        }
    }
}

extension Notification.Name {
    static let prismTogglePopover = Notification.Name("com.mraz.prism.togglePopover")
}

/// 用 Carbon 热键注册全局快捷键；沙盒内可用，不需要辅助功能权限。
@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var registeredChoice: GlobalHotKeyChoice = .off

    /// 返回是否注册成功；快捷键已被系统或其他应用占用时返回 false。
    @discardableResult
    func apply(_ choice: GlobalHotKeyChoice) -> Bool {
        unregister()
        guard let keyCode = choice.keyCode else { return true }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: 0x5052_534D /* 'PRSM' */, id: 1)
        let status = RegisterEventHotKey(
            keyCode,
            choice.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        registeredChoice = choice
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        registeredChoice = .off
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .prismTogglePopover, object: nil)
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
    }
}
