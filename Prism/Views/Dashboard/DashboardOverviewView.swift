import SwiftUI

struct DashboardOverviewView: View {
    @Environment(AppEnvironment.self) private var environment

    private var status: NetworkStatus { environment.networkViewModel.status }

    var body: some View {
        ScrollView {
            if let info = status.info {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "Network Exit"))
                                .font(.title2.weight(.semibold))
                                .accessibilityIdentifier("dashboard.network-exit-title")
                            Text(String(localized: "Your current public route to the internet"))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            StatusBadge(status: status)
                            Text(info.checkedAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if case .verifying(_, let candidateAddress) = status {
                        Label {
                            Text("\(String(localized: "Confirming new exit")) · \(candidateAddress)")
                        } icon: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel(String(localized: "Confirming new exit"))
                    }

                    SectionCard {
                        CountryHeroView(
                            info: info,
                            status: status,
                            flagStyle: environment.settings.countryFlagStyle,
                            showsStatus: false
                        )
                    }

                    HStack(alignment: .top, spacing: 22) {
                        VStack(alignment: .leading, spacing: 13) {
                            Text(String(localized: "Public Addresses"))
                                .font(.subheadline.weight(.semibold))
                            Divider()
                            IPAddressRow(label: String(localized: "Public IPv4"), address: info.addresses.ipv4)
                            Divider()
                            IPAddressRow(label: String(localized: "Public IPv6"), address: info.addresses.ipv6)
                            Divider()
                            InfoRow(label: String(localized: "Route"), value: info.routeMode.label)
                            InfoRow(label: String(localized: "Source"), value: info.exitSource.label)
                        }
                        .frame(maxWidth: .infinity)

                        Divider()

                        VStack(alignment: .leading, spacing: 13) {
                            Text(String(localized: "Network Details"))
                                .font(.subheadline.weight(.semibold))
                            Divider()
                            InfoRow(label: String(localized: "Organization"), value: info.network.organization ?? String(localized: "Unavailable"), allowsWrapping: true)
                            InfoRow(label: String(localized: "ISP"), value: info.network.isp ?? String(localized: "Unavailable"))
                            InfoRow(label: String(localized: "ASN"), value: info.network.asnLabel ?? String(localized: "Unavailable"), monospaced: true)
                            InfoRow(label: String(localized: "Timezone"), value: info.location.timezone ?? String(localized: "Unavailable"))
                            InfoRow(label: String(localized: "Provider"), value: info.providerIdentifier)
                            InfoRow(label: String(localized: "Proxy Risk"), value: privacyLabel(info.privacy))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 4)
                }
                .padding(24)
            } else {
                ContentUnavailableView {
                    Label(status.shortLabel, systemImage: status.symbolName)
                } description: {
                    Text(String(localized: "Prism could not determine the current network exit."))
                } actions: {
                    Button(String(localized: "Try Again")) { environment.refreshCoordinator.triggerManual() }
                }
                .padding(40)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func privacyLabel(_ value: PrivacyClassification) -> String {
        switch value {
        case .suspected: String(localized: "Suspected proxy / VPN")
        case .notDetected: String(localized: "Not detected")
        case .unavailable: String(localized: "Unavailable")
        }
    }
}
