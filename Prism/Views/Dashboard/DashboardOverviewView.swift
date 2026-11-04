import SwiftUI

struct DashboardOverviewView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        .foregroundStyle(StatusPalette.confirming)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(StatusPalette.confirming.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel(String(localized: "Confirming new exit"))
                        .transition(
                            reduceMotion
                                ? AnyTransition.opacity
                                : AnyTransition.move(edge: .top).combined(with: .opacity)
                        )
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
                            detailGrid([
                                (String(localized: "Source"), info.exitSource.label, false)
                            ])
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                        Divider()

                        VStack(alignment: .leading, spacing: 13) {
                            Text(String(localized: "Network Details"))
                                .font(.subheadline.weight(.semibold))
                            Divider()
                            // 线路已在主卡片展示，数据来源移至“网络”设置的诊断信息。
                            detailGrid([
                                (String(localized: "Organization"), info.network.organization ?? String(localized: "Unavailable"), false),
                                (String(localized: "ISP"), info.network.isp ?? String(localized: "Unavailable"), false),
                                (String(localized: "ASN"), info.network.asnLabel ?? String(localized: "Unavailable"), true),
                                (String(localized: "Timezone"), info.location.timezone ?? String(localized: "Unavailable"), false),
                                (String(localized: "Proxy Risk"), privacyLabel(info.privacy), false)
                            ])
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .padding(.horizontal, 4)
                }
                .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: status.isRefreshing)
                .padding(24)
            } else {
                ContentUnavailableView {
                    Label(status.shortLabel, systemImage: status.symbolName)
                } description: {
                    Text(status.isOffline
                        ? String(localized: "No internet connection")
                        : String(localized: "Prism could not determine the current network exit."))
                } actions: {
                    Button(String(localized: "Try Again")) { environment.refreshCoordinator.triggerManual() }
                }
                .padding(40)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 标签列按内容自适应宽度，长值最多两行并在悬停时显示完整内容。
    private func detailGrid(_ rows: [(String, String, Bool)]) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                    Text(row.1)
                        .font(row.2 ? .system(.callout, design: .monospaced) : .callout)
                        .monospacedDigit()
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .help(row.1)
                        .textSelection(.enabled)
                        .contentTransition(.opacity)
                }
            }
        }
        .font(.callout)
    }

    private func privacyLabel(_ value: PrivacyClassification) -> String {
        switch value {
        case .suspected: String(localized: "Suspected proxy / VPN")
        case .notDetected: String(localized: "Not detected")
        case .unavailable: String(localized: "Unavailable")
        }
    }
}
