import AppKit
import SwiftUI

/// 状态语义色的唯一来源：菜单栏角标、状态徽章、确认横幅和失败提示共用，
/// 保证“确认中”（琥珀）与“更新不可用”（橙）在任何位置都能区分。
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

    static var online: Color { Color(nsColor: onlineNSColor) }
    static var confirming: Color { Color(nsColor: confirmingNSColor) }
    static var stale: Color { Color(nsColor: staleNSColor) }

    static func color(for status: NetworkStatus) -> Color {
        switch status {
        case .online: online
        case .loading, .verifying: confirming
        case .stale: stale
        case .offline, .failed: .red
        case .idle: .secondary
        }
    }
}

struct StatusBadge: View {
    let status: NetworkStatus
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label(status.shortLabel, systemImage: status.symbolName)
            .font(.caption.weight(.medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(backgroundColor, in: Capsule())
            .contentTransition(.opacity)
            .accessibilityLabel(status.shortLabel)
    }

    private var foregroundColor: Color {
        StatusPalette.color(for: status)
    }

    private var backgroundColor: Color {
        foregroundColor.opacity(colorScheme == .dark ? 0.18 : 0.13)
    }
}
