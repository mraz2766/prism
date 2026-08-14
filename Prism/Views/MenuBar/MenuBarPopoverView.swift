import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(AppEnvironment.self) private var environment

    private var status: NetworkStatus { environment.networkViewModel.status }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let info = status.info {
                if case .verifying(_, let candidateAddress) = status {
                    Label("\(String(localized: "Confirming new exit")) · \(candidateAddress)", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .accessibilityLabel(String(localized: "Confirming new exit"))
                }
                CountryHeroView(info: info, status: status, compact: true)
                    .contentTransition(.opacity)
                SectionCard {
                    VStack(spacing: 13) {
                        IPAddressRow(label: String(localized: "Public IPv4"), address: info.addresses.ipv4)
                        Divider()
                        IPAddressRow(label: String(localized: "Public IPv6"), address: info.addresses.ipv6)
                    }
                }
                SectionCard {
                    VStack(spacing: 10) {
                        InfoRow(label: String(localized: "ISP"), value: info.network.isp ?? String(localized: "Unavailable"))
                        InfoRow(label: String(localized: "ASN"), value: info.network.asnLabel ?? String(localized: "Unavailable"), monospaced: true)
                        InfoRow(label: String(localized: "Organization"), value: info.network.organization ?? String(localized: "Unavailable"))
                        InfoRow(label: String(localized: "Timezone"), value: info.location.timezone ?? String(localized: "Unavailable"))
                        InfoRow(label: String(localized: "Proxy or VPN"), value: privacyLabel(info.privacy))
                    }
                }
                if case .stale(_, let reason) = status {
                    Label(reason.userDescription, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                unavailableContent
            }
            footer
        }
        .padding(14)
        .frame(width: 360)
        .tint(Color(red: 0.259, green: 0.522, blue: 0.957))
    }

    private var unavailableContent: some View {
        VStack(spacing: 10) {
            Image(systemName: status.symbolName)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(status.shortLabel).font(.headline)
            if case .failed(let reason) = status {
                Text(reason.userDescription).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(String(localized: "Checking your current network exit…"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }

    private var footer: some View {
        HStack {
            if let info = status.info {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(info.checkedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                environment.refreshCoordinator.triggerManual()
            } label: {
                RefreshGlyph(isActive: status.isRefreshing)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: [.command])
            .help(String(localized: "Refresh"))
            .accessibilityLabel(String(localized: "Refresh"))

            Button {
                NotificationCenter.default.post(name: .prismClosePopover, object: nil)
                environment.showDashboard(.history)
            } label: { Image(systemName: "clock.arrow.circlepath") }
                .buttonStyle(.plain)
                .help(String(localized: "History"))
                .accessibilityLabel(String(localized: "History"))

            Button {
                NotificationCenter.default.post(name: .prismClosePopover, object: nil)
                environment.openSettingsAction?()
            } label: { Image(systemName: "gearshape") }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: [.command])
                .help(String(localized: "Settings"))
                .accessibilityLabel(String(localized: "Settings"))
        }
    }

    private func privacyLabel(_ value: PrivacyClassification) -> String {
        switch value {
        case .suspected: String(localized: "Suspected")
        case .notDetected: String(localized: "Not detected")
        case .unavailable: String(localized: "Unavailable")
        }
    }
}

private struct RefreshGlyph: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle = 0.0

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .rotationEffect(.degrees(angle))
            .onAppear { updateAnimation() }
            .onChange(of: isActive) { _, _ in updateAnimation() }
    }

    private func updateAnimation() {
        if isActive && !reduceMotion {
            angle = 0
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                angle = 360
            }
        } else {
            withAnimation(.easeOut(duration: 0.15)) { angle = 0 }
        }
    }
}
