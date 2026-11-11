import SwiftUI

/// 关于与隐私：版本信息、本地优先说明、用到的外部服务与数据来源。
struct AboutSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image("PrismLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            Text("Prism")
                                .font(.headline)
                            Text(verbatim: "v\(Self.appVersion) (\(Self.buildNumber))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("settings.about.version")
                        }
                        Text(String(localized: "Native macOS Network Exit & GeoIP Monitor"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "Open Diagnostics")) {
                        environment.showDashboard(.diagnostics)
                    }
                }
                .padding(.vertical, 2)
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "Local-First Architecture"))
                            .font(.callout.weight(.semibold))
                        Text(String(localized: "No accounts, no telemetry, no tracking, and no cloud syncing."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Exit history and network cache are stored strictly on this Mac."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(StatusPalette.online)
                }
            } header: {
                Text(String(localized: "Privacy"))
            }

            Section {
                providerRow("ipify.org", description: String(localized: "Discovers the current public IPv4 and IPv6 addresses."))
                providerRow("myip.ipip.net", description: String(localized: "Observes the IPv4 address seen by a mainland endpoint."))
                providerRow("ipwho.is · ip.guide · ip.sb · ipip.net", description: String(localized: "Looks up country, city, ISP, organization, ASN, and timezone when the public address changes."))
                providerRow("ipapi.is", description: String(localized: "Performs a best-effort proxy or VPN classification only for a newly seen public address."))
            } header: {
                Text(String(localized: "External Services Used"))
            } footer: {
                Text(String(localized: "IP geolocation is approximate. A suspected proxy or VPN result is not proof and may be wrong."))
            }

            Section(String(localized: "Offline country database")) {
                LabeledContent(String(localized: "Database date"), value: OfflineCountryLookup.datasetDate)
                HStack(spacing: 14) {
                    Text(OfflineCountryLookup.attribution)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Link("DB-IP", destination: OfflineCountryLookup.sourceURL)
                    Link("CC BY 4.0", destination: OfflineCountryLookup.licenseURL)
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func providerRow(_ name: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.system(.callout, design: .monospaced).weight(.medium))
            Text(description).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
