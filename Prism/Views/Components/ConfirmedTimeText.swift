import SwiftUI

/// 稳定状态下不逐秒跳动：一分钟内显示“刚刚确认”，之后按分钟更新。
struct ConfirmedTimeText: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            Text(Self.label(for: date, now: context.date))
        }
    }

    static func label(for date: Date, now: Date = .now) -> String {
        let elapsed = now.timeIntervalSince(date)
        guard elapsed >= 60 else { return String(localized: "Just confirmed") }
        let relative = date.formatted(.relative(presentation: .numeric, unitsStyle: .wide))
        return "\(String(localized: "Confirmed")) \(relative)"
    }
}

extension ProbeLatencyModel {
    static func color(for milliseconds: Int) -> Color {
        switch quality(for: milliseconds) {
        case .good: StatusPalette.online
        case .fair: StatusPalette.confirming
        case .poor: StatusPalette.stale
        }
    }
}

/// 出口探测往返耗时的小标签。
struct LatencyLabel: View {
    let milliseconds: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(ProbeLatencyModel.color(for: milliseconds))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(verbatim: "\(milliseconds) ms")
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help(String(localized: "Round-trip time of the latest exit probe"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Probe latency"))
        .accessibilityValue("\(milliseconds) ms")
    }
}
