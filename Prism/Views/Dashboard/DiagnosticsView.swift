import SwiftUI

/// 只读诊断信息：当前路线、归属地服务健康度与离线国家库。
struct DiagnosticsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var providerHealth: [ProviderHealthSnapshot] = []

    private var status: NetworkStatus { environment.networkViewModel.status }

    var body: some View {
        Form {
            if let info = status.info {
                Section(String(localized: "Current route")) {
                    LabeledContent(String(localized: "Route"), value: info.routeMode.label)
                    LabeledContent(String(localized: "Probe source"), value: info.exitSource.label)
                    LabeledContent(String(localized: "Last confirmed")) {
                        ConfirmedTimeText(date: info.checkedAt).foregroundStyle(.secondary)
                    }
                    if let latency = environment.latencyModel.milliseconds {
                        LabeledContent(String(localized: "Probe latency")) {
                            LatencyLabel(milliseconds: latency)
                        }
                    }
                    LabeledContent(String(localized: "Location source"), value: info.locationSource.displayLabel)
                    if let checkedAt = info.locationCheckedAt {
                        LabeledContent(info.locationSource.timestampLabel) {
                            Text(checkedAt, format: .dateTime)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !info.providerIdentifier.isEmpty {
                        LabeledContent(String(localized: "Active Provider"), value: info.providerIdentifier)
                    }
                }
            }

            Section {
                if case .locationUnavailable(_, let reason) = status {
                    Text(reason.locationDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("settings.location-diagnostic")
                } else if case .locating = status {
                    Text(String(localized: "Refreshing optional location details in background"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(providerHealth) { provider in
                    HStack {
                        Circle()
                            .fill(provider.isCircuitOpen ? StatusPalette.confirming : StatusPalette.online)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)

                        Text(provider.identifier)
                            .font(.body.monospaced())

                        Spacer()

                        if provider.isCircuitOpen {
                            Text(String(localized: "Circuit Open"))
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(StatusPalette.confirming.opacity(0.15), in: Capsule())
                                .foregroundStyle(StatusPalette.confirming)
                        } else if let latency = provider.lastLatencyMilliseconds {
                            Text("\(latency) ms")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            Text(String(localized: "Standby"))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(String(localized: "GeoIP Providers"))
            } footer: {
                Text(String(localized: "Local country first, online details in background"))
            }

            Section(String(localized: "Offline country database")) {
                LabeledContent(String(localized: "Database date"), value: OfflineCountryLookup.datasetDate)
                Text(String(localized: "Country information is available locally; city and network details update in the background."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "How detection works")) {
                Text(String(localized: "Prism checks IPv4 and IPv6 independently. Location lookup prefers IPv4 and uses IPv6 when IPv4 is unavailable."))
                    .font(.callout).foregroundStyle(.secondary)
                Text(String(localized: "Prism shows the domestic exit after two confirmed overseas failures with domestic access, and returns to the overseas exit when it recovers."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: status) {
            providerHealth = await environment.providerHealth.snapshots(
                order: ["ipwho.is", "ip.guide", "ip.sb", "ipip.net"]
            )
        }
    }
}
