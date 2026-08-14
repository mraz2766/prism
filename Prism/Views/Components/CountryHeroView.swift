import SwiftUI

struct CountryHeroView: View {
    let info: NetworkInfo
    let status: NetworkStatus
    var compact = false
    var showsStatus = true

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 12 : 18) {
            Text(CountryFlag.emoji(for: info.location.countryCode) ?? "◎")
                .font(compact ? .system(size: 30) : .system(size: 42))
                .accessibilityLabel(info.location.localizedCountry())
            .frame(width: compact ? 48 : 64, height: compact ? 48 : 64)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(info.location.localizedCountry())
                        .font(compact ? .title3.weight(.bold) : .title2.weight(.bold))
                        .lineLimit(1)
                    if let city = info.location.city, !city.isEmpty {
                        Text(city)
                            .font(compact ? .subheadline : .headline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 8) {
                    Label(info.routeMode.label, systemImage: routeSymbol)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.4), in: Capsule())
                        .foregroundStyle(.secondary)

                    if let timezone = info.location.timezone, !compact {
                        Label(timezone, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 8)
            if showsStatus { StatusBadge(status: status) }
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
