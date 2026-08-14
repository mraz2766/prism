import SwiftUI

struct PrivacySettingsView: View {
    var body: some View {
        Form {
            Section {
                Label(String(localized: "Local first"), systemImage: "internaldrive")
                    .font(.headline)
                Text(String(localized: "Prism has no account, analytics, advertising, telemetry, or browsing-history collection."))
                Text(String(localized: "Exit history and the last successful result are stored only on this Mac."))
            }
            Section(String(localized: "Network requests")) {
                provider("ipify", description: String(localized: "Discovers the current public IPv4 and IPv6 addresses."))
                provider("ipwho.is / ip.guide / ipip.net", description: String(localized: "Looks up country, city, ISP, organization, ASN, and timezone when the public address changes."))
                provider("ipapi.is", description: String(localized: "Performs a best-effort proxy or VPN classification only for a newly seen public address."))
            }
            Section {
                Text(String(localized: "GeoIP location is requested fresh and is not reused from a city cache."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(String(localized: "IP geolocation is approximate. A suspected proxy or VPN result is not proof and may be wrong."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func provider(_ name: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.system(.body, design: .monospaced).weight(.medium))
            Text(description).font(.caption).foregroundStyle(.secondary)
        }
    }
}
