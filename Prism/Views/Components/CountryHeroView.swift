import SwiftUI

struct CountryHeroView: View {
    let info: NetworkInfo
    let status: NetworkStatus
    var compact = false
    var showsStatus = true

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 12 : 18) {
            Text(CountryFlag.emoji(for: info.location.countryCode) ?? "◎")
                .font(compact ? .system(size: 34) : .system(size: 48))
                .accessibilityLabel(info.location.localizedCountry())
            VStack(alignment: .leading, spacing: 3) {
                Text(info.location.localizedCountry())
                    .font(compact ? .title2.weight(.semibold) : .largeTitle.weight(.semibold))
                    .lineLimit(1)
                if let city = info.location.city, !city.isEmpty {
                    Text(city).font(.callout).foregroundStyle(.secondary)
                }
                Label(info.routeMode.label, systemImage: routeSymbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if compact {
                    Text(String(localized: "Current network exit"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
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
