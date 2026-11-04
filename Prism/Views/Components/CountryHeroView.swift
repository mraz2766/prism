import SwiftUI

struct CountryHeroView: View {
    let info: NetworkInfo
    let status: NetworkStatus
    var flagStyle: CountryFlagStyle = .sticker
    var cityOverride: String? = nil
    var compact = false
    var showsStatus = true
    var showsRoute = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 出口或城市变化时触发过渡；仅时间戳变化不会产生动画。
    private var transitionKey: String {
        "\(info.id)|\(cityOverride ?? info.location.city ?? "")"
    }

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 12 : 18) {
            Group {
                if info.hasLocation {
                    CountryFlagView(
                        countryCode: info.location.countryCode,
                        style: flagStyle,
                        diameter: compact ? 32 : 44,
                        containerSize: compact ? CGSize(width: 48, height: 48) : CGSize(width: 64, height: 64)
                    )
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: compact ? 28 : 38))
                        .foregroundStyle(.secondary)
                        .frame(width: compact ? 48 : 64, height: compact ? 48 : 64)
                        .accessibilityLabel(String(localized: "Location unavailable"))
                }
            }
            .id(info.location.countryCode)
            .transition(
                reduceMotion
                    ? AnyTransition.opacity
                    : AnyTransition.asymmetric(
                        insertion: AnyTransition.opacity.combined(with: .scale(scale: 0.82)),
                        removal: AnyTransition.opacity.combined(with: .scale(scale: 1.08))
                    )
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(locationTitle)
                        .font(compact ? .title3.weight(.bold) : .title2.weight(.bold))
                        .lineLimit(1)
                        .contentTransition(.opacity)
                    if let city = cityOverride ?? info.location.city, !city.isEmpty {
                        Text(city)
                            .font(compact ? .subheadline : .headline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                    }
                }

                if showsRetainedLocation, let checkedAt = info.locationCheckedAt {
                    Text("\(String(localized: "Location updated")) · \(checkedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityIdentifier("location.last-success")
                }

                if showsRoute || (!compact && info.location.timezone != nil) {
                    HStack(spacing: 8) {
                        if showsRoute {
                            Label(info.routeMode.label, systemImage: routeSymbol)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.4), in: Capsule())
                                .foregroundStyle(.secondary)
                        }

                        if let timezone = info.location.timezone, !compact {
                            Label(timezone, systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            if showsStatus { StatusBadge(status: status) }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.32), value: transitionKey)
    }

    private var locationTitle: String {
        if info.hasLocation { return info.location.localizedCountry() }
        if case .locating = status { return String(localized: "Location pending") }
        return String(localized: "Location unavailable")
    }

    private var showsRetainedLocation: Bool {
        guard info.hasLocation else { return false }
        return switch status {
        case .locating, .locationUnavailable, .stale: true
        default: false
        }
    }

    private var routeSymbol: String {
        switch info.routeMode {
        case .proxy: "arrow.triangle.branch"
        case .direct: "point.3.connected.trianglepath.dotted"
        case .split: "arrow.triangle.swap"
        case .unknown: "questionmark.circle"
        }
    }
}

#Preview {
    CountryHeroView(info: .preview, status: .online(.preview))
        .padding().frame(width: 520)
}
