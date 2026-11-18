import AppKit
import SwiftUI

/// 关于与隐私：版本信息、本地优先说明、用到的外部服务与数据来源。
struct AboutSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoHovered = false
    @State private var copiedVersion = false

    var body: some View {
        SettingsPage {
            header

            SettingsGroup(title: String(localized: "Privacy"), systemImage: "lock.shield") {
                privacyRow(
                    "person.crop.circle.badge.xmark",
                    title: String(localized: "Local-First Architecture"),
                    detail: String(localized: "No accounts, no telemetry, no tracking, and no cloud syncing.")
                )
                SettingsDivider()
                privacyRow(
                    "internaldrive",
                    title: String(localized: "Stored only on this Mac"),
                    detail: String(localized: "Exit history and network cache are stored strictly on this Mac.")
                )
                SettingsDivider()
                privacyRow(
                    "location.slash",
                    title: String(localized: "Approximate location"),
                    detail: String(localized: "IP geolocation is approximate. A suspected proxy or VPN result is not proof and may be wrong.")
                )
            }

            SettingsGroup(title: String(localized: "External Services Used"), systemImage: "network") {
                serviceRow("ipify.org", icon: "globe", detail: String(localized: "Discovers the current public IPv4 and IPv6 addresses."))
                SettingsDivider()
                serviceRow("myip.ipip.net", icon: "house", detail: String(localized: "Observes the IPv4 address seen by a mainland endpoint."))
                SettingsDivider()
                serviceRow("ipwho.is · ip.guide · ip.sb · ipip.net", icon: "mappin.and.ellipse", detail: String(localized: "Looks up country, city, ISP, organization, ASN, and timezone when the public address changes."))
                SettingsDivider()
                serviceRow("ipapi.is", icon: "shield.lefthalf.filled", detail: String(localized: "Performs a best-effort proxy or VPN classification only for a newly seen public address."))
                SettingsDivider()
                serviceRow("Baidu · Google · Gemini · ChatGPT", icon: "speedometer", detail: String(localized: "Small response-time requests only when you start a network test. No bandwidth test."))
                SettingsDivider()
                serviceRow("Cloudflare STUN · Google STUN", icon: "dot.radiowaves.left.and.right", detail: String(localized: "WebRTC ICE discovery during a manual network test. Candidates stay in memory; no camera or microphone access."))
            }

            SettingsGroup(title: String(localized: "Offline country database"), systemImage: "externaldrive") {
                SettingsRow(title: String(localized: "Database date")) {
                    Text(OfflineCountryLookup.datasetDate)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                SettingsDivider()
                SettingsRow(title: OfflineCountryLookup.attribution) {
                    HStack(spacing: 14) {
                        Link("DB-IP", destination: OfflineCountryLookup.sourceURL)
                        Link("CC BY 4.0", destination: OfflineCountryLookup.licenseURL)
                    }
                }
            }
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 14) {
            Image("PrismLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: logoHovered ? 8 : 4, y: logoHovered ? 4 : 2)
                .rotation3DEffect(
                    .degrees(logoHovered && !reduceMotion ? 10 : 0),
                    axis: (x: -0.4, y: 1, z: 0)
                )
                .scaleEffect(logoHovered && !reduceMotion ? 1.05 : 1)
                .onHover { hovering in
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.35)) {
                        logoHovered = hovering
                    }
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Prism")
                        .font(.title2.weight(.semibold))
                    Button(action: copyVersion) {
                        HStack(spacing: 4) {
                            Text(verbatim: "v\(Self.appVersion) (\(Self.buildNumber))")
                                .monospacedDigit()
                            Image(systemName: copiedVersion ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9, weight: .semibold))
                                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                        }
                        .tagCapsule(
                            foreground: copiedVersion ? AnyShapeStyle(StatusPalette.online) : AnyShapeStyle(.secondary),
                            background: Color.primary.opacity(0.06)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Copy version"))
                    .accessibilityIdentifier("settings.about.version")
                }
                Text(String(localized: "Native macOS Network Exit & GeoIP Monitor"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                environment.showDashboard(.diagnostics)
            } label: {
                Label(String(localized: "Open Diagnostics"), systemImage: "stethoscope")
            }
            .controlSize(.regular)
        }
        .padding(14)
        .background(
            ZStack {
                SettingsCardBackground(cornerRadius: 14)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.14), Color.accentColor.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        )
    }

    private func copyVersion() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Prism \(Self.appVersion) (\(Self.buildNumber))", forType: .string)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { copiedVersion = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { copiedVersion = false }
        }
    }

    // MARK: 行

    private func privacyRow(_ icon: String, title: String, detail: String) -> some View {
        iconRow(icon, tint: StatusPalette.online, title: title, detail: detail, monospacedTitle: false)
    }

    private func serviceRow(_ name: String, icon: String, detail: String) -> some View {
        iconRow(icon, tint: .accentColor, title: name, detail: detail, monospacedTitle: false)
    }

    private func iconRow(_ icon: String, tint: Color, title: String, detail: String, monospacedTitle: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
