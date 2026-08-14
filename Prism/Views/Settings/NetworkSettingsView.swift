import SwiftUI

struct NetworkSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var providerHealth: [ProviderHealthSnapshot] = []

    var body: some View {
        Form {
            if let info = environment.networkViewModel.status.info {
                Section(String(localized: "Current route")) {
                    LabeledContent(String(localized: "Route"), value: info.routeMode.label)
                    LabeledContent(String(localized: "Probe source"), value: info.exitSource.label)
                    LabeledContent(String(localized: "Last confirmed")) {
                        Text(info.checkedAt, style: .relative).foregroundStyle(.secondary)
                    }
                }
            }
            Section(String(localized: "Geo IP provider")) {
                LabeledContent(String(localized: "Mode"), value: String(localized: "Automatic fallback"))
                DisclosureGroup(String(localized: "Advanced provider details")) {
                    LabeledContent(String(localized: "Provider order"), value: "ipwho.is → ip.guide → ipip.net")
                    ForEach(providerHealth) { provider in
                        LabeledContent(provider.identifier) {
                            Text(healthDescription(provider))
                                .foregroundStyle(provider.isCircuitOpen ? .orange : .secondary)
                        }
                    }
                }
                if let info = environment.networkViewModel.status.info {
                    LabeledContent(String(localized: "Last provider"), value: info.providerIdentifier)
                }
            }
            Section {
                Text(String(localized: "Prism checks IPv4 and IPv6 independently. Location lookup prefers IPv4 and uses IPv6 when IPv4 is unavailable."))
                    .font(.callout).foregroundStyle(.secondary)
                Text(String(localized: "When overseas address services are unavailable, Prism uses a mainland-accessible IPIP fallback."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task(id: environment.networkViewModel.status.info?.checkedAt) {
            providerHealth = await environment.providerHealth.snapshots(
                order: ["ipwho.is", "ip.guide", "ipip.net"]
            )
        }
    }

    private func healthDescription(_ provider: ProviderHealthSnapshot) -> String {
        if provider.isCircuitOpen { return String(localized: "Temporarily paused") }
        if let latency = provider.lastLatencyMilliseconds {
            return "\(latency) ms"
        }
        return String(localized: "Not checked yet")
    }
}
