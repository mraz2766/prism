import SwiftUI

struct StatusBadge: View {
    let status: NetworkStatus

    var body: some View {
        Label(status.shortLabel, systemImage: status.symbolName)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.1), in: Capsule())
            .accessibilityLabel(status.shortLabel)
    }

    private var color: Color {
        switch status {
        case .online: .green
        case .loading, .verifying: .yellow
        case .offline, .failed: .red
        case .stale: .orange
        case .idle: .secondary
        }
    }
}
