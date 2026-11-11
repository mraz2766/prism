import SwiftUI

struct DashboardOverviewView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var recentEntries: [NetworkHistoryEntry] = []

    private var status: NetworkStatus { environment.networkViewModel.status }
    private var accent: Color { environment.settings.accentColorChoice.color }

    var body: some View {
        ScrollView {
            if let info = status.info {
                content(for: info)
            } else {
                unavailableContent
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            for await values in environment.historyStore.stream() {
                recentEntries = Array(values.sorted { $0.recordedAt > $1.recordedAt }.prefix(3))
            }
        }
    }

    private func content(for info: NetworkInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text(String(localized: "Network Exit"))
                    .font(.headline)
                    .accessibilityIdentifier("dashboard.network-exit-title")
                Spacer()
                if let latency = environment.latencyModel.milliseconds,
                   info.exitSource != .domesticFallback {
                    LatencyLabel(milliseconds: latency)
                }
                ConfirmedTimeText(date: info.checkedAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StatusBadge(status: status)
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

            SectionCard(accent: accent) {
                CountryHeroView(
                    info: info,
                    status: status,
                    flagStyle: environment.settings.countryFlagStyle,
                    cityOverride: environment.cityLocalizer.displayCity(for: info),
                    showsStatus: false,
                    outsideExpectedRegion: environment.isOutsideExpectedRegion
                )
            }

            HStack(alignment: .top, spacing: 14) {
                SectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        cardTitle(String(localized: "Public exit"), systemImage: "globe")
                        IPAddressRow(label: String(localized: "Public IPv4"), address: info.addresses.ipv4)
                        Divider()
                        IPAddressRow(label: String(localized: "Public IPv6"), address: info.addresses.ipv6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                SectionCard {
                    domesticCard(currentIPv4: info.addresses.ipv4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    cardTitle(String(localized: "Network Details"), systemImage: "point.3.connected.trianglepath.dotted")
                    detailGrid(detailRows(for: info))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !recentEntries.isEmpty {
                recentChanges
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: status.isRefreshing)
        .padding(20)
    }

    private func cardTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func domesticCard(currentIPv4: String?) -> some View {
        let domestic = environment.domesticIPv4ViewModel.status
        VStack(alignment: .leading, spacing: 12) {
            cardTitle(String(localized: "Domestic exit"), systemImage: "house")
            IPAddressRow(
                label: String(localized: "Domestic exit IPv4"),
                address: domestic.info?.address,
                placeholder: domestic.isLoading || domestic == .idle
                    ? String(localized: "Detecting")
                    : nil,
                accessibilityIdentifier: "dashboard.domestic-ipv4-row"
            )
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                if let relation = domestic.detailLabel(currentIPv4: currentIPv4) {
                    Text(relation)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                } else if case .failed(_, let reason) = domestic {
                    Text(reason.userDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let checkedAt = domestic.info?.checkedAt {
                    Text("\(String(localized: "Checked")) \(checkedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentTransition(.opacity)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: domestic)
    }

    private var recentChanges: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                cardTitle(String(localized: "Recent changes"), systemImage: "clock.arrow.circlepath")
                Spacer()
                Button(String(localized: "View all")) {
                    environment.dashboardNavigation.destination = .history
                }
                .buttonStyle(.link)
                .font(.callout)
            }
            VStack(spacing: 0) {
                ForEach(Array(recentEntries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider().padding(.leading, 42) }
                    HStack(spacing: 12) {
                        CountryFlagView(
                            countryCode: entry.countryCode,
                            style: environment.settings.countryFlagStyle,
                            diameter: 20,
                            containerSize: CGSize(width: 30, height: 26)
                        )
                        Text(entry.locationLabel(using: environment.cityLocalizer))
                            .font(.callout)
                            .lineLimit(1)
                        Text(entry.addresses.preferredForLookup ?? "—")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(entry.recordedAt.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 7)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
        }
        .padding(.top, 2)
    }

    /// 加载中、离线、失败分别呈现，启动时不再误报“无法确定出口”。
    @ViewBuilder
    private var unavailableContent: some View {
        Group {
            switch status {
            case .idle, .loading, .verifying:
                VStack(spacing: 12) {
                    ProgressView()
                    Text(String(localized: "Checking your current network exit…"))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("dashboard.loading")
            case .offline:
                ContentUnavailableView {
                    Label(String(localized: "Offline"), systemImage: "wifi.slash")
                } description: {
                    Text(String(localized: "No internet connection"))
                    Text(String(localized: "Prism will check again as soon as the network returns."))
                }
            default:
                ContentUnavailableView {
                    Label(String(localized: "Exit not confirmed"), systemImage: "questionmark.circle")
                } description: {
                    if case .failed(let reason) = status {
                        Text(reason.userDescription)
                    } else {
                        Text(String(localized: "Prism could not determine the current network exit."))
                    }
                } actions: {
                    Button(String(localized: "Try Again")) { environment.refreshCoordinator.triggerManual() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 120)
        .padding(.horizontal, 40)
    }

    private struct DetailRow: Identifiable {
        let label: String
        let value: String
        var monospaced = false
        var id: String { label }
    }

    /// 只列出有值的字段，不再整列重复“不可用”。
    private func detailRows(for info: NetworkInfo) -> [DetailRow] {
        var rows: [DetailRow] = []
        func add(_ label: String, _ value: String?, monospaced: Bool = false) {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
            rows.append(DetailRow(label: label, value: value, monospaced: monospaced))
        }
        add(String(localized: "ISP"), info.network.isp)
        if info.network.organization != info.network.isp {
            add(String(localized: "Organization"), info.network.organization)
        }
        add(String(localized: "ASN"), info.network.asnLabel, monospaced: true)
        add(String(localized: "Timezone"), info.location.timezone)
        switch info.privacy {
        case .suspected: add(String(localized: "Proxy Risk"), String(localized: "Suspected proxy / VPN"))
        case .notDetected: add(String(localized: "Proxy Risk"), String(localized: "Not detected"))
        case .unavailable: break
        }
        if info.routeMode != .unknown {
            add(String(localized: "Route"), info.routeMode.label)
        }
        add(String(localized: "Source"), info.exitSource == .unknown ? nil : info.exitSource.label)
        return rows
    }

    /// 两列排布，长值最多两行并在悬停时显示完整内容。
    @ViewBuilder
    private func detailGrid(_ rows: [DetailRow]) -> some View {
        if rows.isEmpty {
            Text(String(localized: "Network details will appear once the lookup completes."))
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 24, alignment: .topLeading),
                    GridItem(.flexible(), alignment: .topLeading)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(row.value)
                            .font(row.monospaced ? .system(.callout, design: .monospaced) : .callout)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .help(row.value)
                            .textSelection(.enabled)
                            .contentTransition(.opacity)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

extension NetworkHistoryEntry {
    /// “国家 · 城市”，城市名与界面其它位置保持同一种语言。
    @MainActor
    func locationLabel(using localizer: CityLocalizer, locale: Locale = .autoupdatingCurrent) -> String {
        guard !countryCode.isEmpty else { return String(localized: "Country not yet identified") }
        let country = locale.localizedString(forRegionCode: countryCode) ?? countryCode
        guard let city = localizer.displayCity(city, countryCode: countryCode), !city.isEmpty else { return country }
        return "\(country) · \(city)"
    }
}
