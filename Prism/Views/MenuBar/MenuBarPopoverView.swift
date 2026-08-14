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
                SectionCard(horizontalPadding: 14, verticalPadding: 12) {
                    VStack(spacing: 12) {
                        IPAddressRow(label: String(localized: "Public IPv4"), address: info.addresses.ipv4)
                        Divider()
                        IPAddressRow(label: String(localized: "Public IPv6"), address: info.addresses.ipv6)
                    }
                }
                SectionCard(horizontalPadding: 14, verticalPadding: 12) {
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
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(environment.settings.accentColorChoice.color)
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
        HStack(alignment: .center) {
            if let info = status.info {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(info.checkedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            PopoverActionButton(
                systemName: "arrow.clockwise",
                help: String(localized: "Refresh"),
                shortcutKey: "r",
                isSpinning: status.isRefreshing,
                isDisabled: status.isRefreshing
            ) {
                environment.refreshCoordinator.triggerManual()
            }

            PopoverActionButton(
                systemName: "clock.arrow.circlepath",
                help: String(localized: "History")
            ) {
                NotificationCenter.default.post(name: .prismClosePopover, object: nil)
                Task { @MainActor in
                    await Task.yield()
                    environment.showDashboard(.history)
                }
            }

            PopoverActionButton(
                systemName: "gearshape",
                help: String(localized: "Settings"),
                shortcutKey: ","
            ) {
                NotificationCenter.default.post(name: .prismClosePopover, object: nil)
                Task { @MainActor in
                    await Task.yield()
                    environment.openSettingsAction?()
                }
            }
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

private struct PopoverActionButton: View {
    let systemName: String
    let help: String
    var shortcutKey: KeyEquivalent?
    var isSpinning = false
    var isDisabled = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if isSpinning {
                    RefreshGlyph(isActive: true)
                } else {
                    Image(systemName: systemName)
                }
            }
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(isHovered ? .primary : .secondary)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(PopoverActionButtonStyle(isHovered: isHovered))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.65 : 1)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .help(help)
        .accessibilityLabel(help)
        .keyboardShortcutIfPresent(shortcutKey)
    }
}

private struct PopoverActionButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered || configuration.isPressed ? Color.primary.opacity(0.08) : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private extension View {
    @ViewBuilder
    func keyboardShortcutIfPresent(_ key: KeyEquivalent?) -> some View {
        if let key {
            keyboardShortcut(key, modifiers: .command)
        } else {
            self
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
