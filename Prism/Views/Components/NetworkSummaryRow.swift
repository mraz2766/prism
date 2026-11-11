import SwiftUI

/// 运营商、ASN 与代理风险的一行摘要，用于判断“现在走的是哪个节点”。
struct NetworkSummaryRow: View {
    let info: NetworkInfo

    static func hasContent(_ info: NetworkInfo) -> Bool {
        carrier(for: info) != nil || info.network.asn != nil || info.privacy == .suspected
    }

    static func carrier(for info: NetworkInfo) -> String? {
        [info.network.isp, info.network.organization]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Network"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if let carrier = Self.carrier(for: info) {
                        Text(carrier)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(carrier)
                    }
                    if let asn = info.network.asnLabel {
                        Text(verbatim: asn)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
                .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            if info.privacy == .suspected {
                Label(String(localized: "Proxy / VPN"), systemImage: "shield.lefthalf.filled")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.tint.opacity(0.14), in: Capsule())
                    .foregroundStyle(.tint)
                    .fixedSize()
                    .help(String(localized: "Suspected proxy / VPN"))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("network.summary")
    }
}
