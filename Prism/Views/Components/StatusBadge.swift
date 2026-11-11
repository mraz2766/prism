import AppKit
import SwiftUI

/// 出口状态与可选的位置更新分开呈现：位置服务失败不改变在线状态。
enum StatusPalette {
    static var onlineNSColor: NSColor { NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [
            .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua
        ])
        if match == .darkAqua {
            return NSColor(red: 0.38, green: 0.90, blue: 0.50, alpha: 1)
        } else if match == .accessibilityHighContrastDarkAqua {
            return NSColor(red: 0.52, green: 0.96, blue: 0.62, alpha: 1)
        } else if match == .accessibilityHighContrastAqua {
            return NSColor(red: 0.03, green: 0.34, blue: 0.16, alpha: 1)
        }
        return NSColor(red: 0.03, green: 0.42, blue: 0.16, alpha: 1)
    } }

    /// 动态琥珀色：浅色模式下对比度 > 4.5:1，深色模式下明亮醒目。
    static var confirmingNSColor: NSColor { NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1)
            : NSColor(red: 0.71, green: 0.33, blue: 0.04, alpha: 1)
    } }

    static var staleNSColor: NSColor { NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 1.00, green: 0.45, blue: 0.30, alpha: 1)
            : NSColor(red: 0.78, green: 0.22, blue: 0.08, alpha: 1)
    } }

    /// 断网与越界提醒共用的警示红，深浅色下都保持足够对比度。
    static var offlineNSColor: NSColor { NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 1.00, green: 0.42, blue: 0.40, alpha: 1)
            : NSColor(red: 0.76, green: 0.11, blue: 0.11, alpha: 1)
    } }

    static var offline: Color { Color(nsColor: offlineNSColor) }
    static var online: Color { Color(nsColor: onlineNSColor) }
    static var confirming: Color { Color(nsColor: confirmingNSColor) }
    static var stale: Color { Color(nsColor: staleNSColor) }

    static func color(for status: NetworkStatus) -> Color {
        switch status {
        case .online, .locating, .locationUnavailable: online
        case .loading, .verifying: confirming
        case .offline: offline
        case .stale: stale
        case .idle, .failed: .secondary
        }
    }
}

struct StatusBadge: View {
    let status: NetworkStatus
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label(status.shortLabel, systemImage: status.symbolName)
            .font(.caption.weight(.medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(backgroundColor, in: Capsule())
            .contentTransition(.opacity)
            // 确认完成时由琥珀色平滑过渡到绿色。
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: status.symbolName)
            .accessibilityLabel(status.shortLabel)
            .accessibilityIdentifier("network.status")
            .accessibilityValue(status.symbolName)
    }

    private var foregroundColor: Color {
        StatusPalette.color(for: status)
    }

    private var backgroundColor: Color {
        foregroundColor.opacity(colorScheme == .dark ? 0.18 : 0.13)
    }
}
