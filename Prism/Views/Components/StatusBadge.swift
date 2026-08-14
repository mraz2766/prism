import SwiftUI

struct StatusBadge: View {
    let status: NetworkStatus
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Label(status.shortLabel, systemImage: status.symbolName)
            .font(.caption.weight(.medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(backgroundColor, in: Capsule())
            .accessibilityLabel(status.shortLabel)
    }

    private var foregroundColor: Color {
        switch status {
        case .online:
            colorScheme == .dark
                ? Color(red: 0.38, green: 0.90, blue: 0.50)
                : Color(red: 0.03, green: contrast == .increased ? 0.34 : 0.42, blue: 0.16)
        case .loading, .verifying:
            // 动态琥珀色：浅色模式下对比度 > 4.5:1，深色模式下明亮醒目
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1.0)
                    : NSColor(red: 0.71, green: 0.33, blue: 0.04, alpha: 1.0)
            })
        case .offline, .failed:
            .red
        case .stale:
            .orange
        case .idle:
            .secondary
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .online:
            foregroundColor.opacity(colorScheme == .dark ? 0.18 : 0.13)
        case .loading, .verifying:
            Color.orange.opacity(0.12)
        case .offline, .failed:
            .red.opacity(0.12)
        case .stale:
            .orange.opacity(0.12)
        case .idle:
            .secondary.opacity(0.12)
        }
    }
}
