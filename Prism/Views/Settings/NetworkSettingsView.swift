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
                    LabeledContent(String(localized: "Location source"), value: info.locationSource.displayLabel)
                    if let checkedAt = info.locationCheckedAt {
                        LabeledContent(info.locationSource.timestampLabel) {
                            Text(checkedAt, format: .dateTime)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(String(localized: "GeoIP Providers")) {
                LabeledContent(String(localized: "Strategy"), value: String(localized: "Local country first, online details in background"))

                DisclosureGroup(String(localized: "Provider Health & Latency")) {
                    VStack(alignment: .leading, spacing: 8) {
                        if case .locationUnavailable(_, let reason) = environment.networkViewModel.status {
                            Text(reason.locationDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("settings.location-diagnostic")
                        } else if case .locating = environment.networkViewModel.status {
                            Text(String(localized: "Refreshing optional location details in background"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
                    LabeledContent(String(localized: "Active Provider"), value: info.providerIdentifier.isEmpty ? String(localized: "Unavailable") : info.providerIdentifier)
                }
            }

            Section(String(localized: "Offline country database")) {
                LabeledContent(String(localized: "Database date"), value: OfflineCountryLookup.datasetDate)
                Text(String(localized: "Country information is available locally; city and network details update in the background."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text(String(localized: "Prism checks IPv4 and IPv6 independently. Location lookup prefers IPv4 and uses IPv6 when IPv4 is unavailable."))
                    .font(.callout).foregroundStyle(.secondary)
                Text(String(localized: "Prism observes the domestic endpoint separately. A slow overseas probe does not prove that the route has changed."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task(id: environment.networkViewModel.status) {
            providerHealth = await environment.providerHealth.snapshots(
                order: ["ipwho.is", "ip.guide", "ip.sb", "ipip.net"]
            )
        }
    }
}
