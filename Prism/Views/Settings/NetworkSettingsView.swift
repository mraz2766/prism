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

            Section(String(localized: "GeoIP Providers")) {
                LabeledContent(String(localized: "Strategy"), value: String(localized: "Multi-Source Priority Fallback"))

                DisclosureGroup(String(localized: "Provider Health & Latency")) {
                    VStack(spacing: 8) {
                        ForEach(providerHealth) { provider in
                            HStack {
                                Circle()
                                    .fill(provider.isCircuitOpen ? Color.orange : Color.green)
                                    .frame(width: 7, height: 7)

                                Text(provider.identifier)
                                    .font(.body.monospaced())

                                Spacer()

                                if provider.isCircuitOpen {
                                    Text(String(localized: "Circuit Open"))
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.orange)
                                } else if let latency = provider.lastLatencyMilliseconds {
                                    Text("\(latency) ms")
                                        .font(.caption.monospacedDigit())
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color(nsColor: .quaternaryLabelColor), in: Capsule())
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(String(localized: "Standby"))
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let info = environment.networkViewModel.status.info {
                    LabeledContent(String(localized: "Active Provider"), value: info.providerIdentifier)
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
}
