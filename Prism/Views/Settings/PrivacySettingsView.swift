import SwiftUI

struct PrivacySettingsView: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.title2)
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "Local-First Architecture"))
                            .font(.headline)
                        Text(String(localized: "No accounts, no telemetry, no tracking, and no cloud syncing."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Text(String(localized: "Exit history and network cache are stored strictly on this Mac."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "External Services Used")) {
                providerRow("ipify.org", icon: "network", description: String(localized: "Discovers the current public IPv4 and IPv6 addresses."))
                providerRow("myip.ipip.net", icon: "arrow.left.arrow.right", description: String(localized: "Observes the IPv4 address seen by a mainland endpoint."))
                providerRow("ipwho.is / ip.guide / ipip.net", icon: "globe.asia.australia.fill", description: String(localized: "Looks up country, city, ISP, organization, ASN, and timezone when the public address changes."))
                providerRow("ipapi.is", icon: "shield.lefthalf.filled", description: String(localized: "Performs a best-effort proxy or VPN classification only for a newly seen public address."))
            }

            Section {
                Text(String(localized: "GeoIP location is requested fresh and is not reused from a city cache."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(String(localized: "IP geolocation is approximate. A suspected proxy or VPN result is not proof and may be wrong."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func providerRow(_ name: String, icon: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(.body, design: .monospaced).weight(.medium))
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
