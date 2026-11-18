import SwiftUI

/// 网络测试页：顶部仪表给出整体结论，下方站点卡片展示每轮采样，最后用区间图横向对比各站点。
struct NetworkTestView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var expandedTargets: Set<String> = []

    private var model: NetworkTestViewModel { environment.networkTestViewModel }
    private var accent: Color { environment.settings.accentColorChoice.color }
    private var summary: NetworkTestSummary { NetworkTestSummary(results: model.results) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if model.phase == .invalidated {
                    invalidatedBanner
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                sitesSection
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: model.phase)
        .accessibilityIdentifier("network-test.page")
    }

    // MARK: 顶部仪表

    private var hero: some View {
        HStack(alignment: .center, spacing: 28) {
            NetworkTestDial(
                phase: model.phase,
                completed: model.completedSamples,
                total: model.totalSamples,
                summary: summary,
                phaseLabel: phaseLabel,
                accent: accent
            )
            .frame(width: 172, height: 172)
            .padding(.leading, 6)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(String(localized: "Network Test"))
                            .font(.title2.bold())
                        webRTCStatus
                    }
                    Text("\(String(localized: "Response time · stability")) · \(String(localized: "Three samples per site. No bandwidth test."))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    statTile(
                        String(localized: "Overall median"),
                        value: LatencyFormat.seconds(summary.overallMedian),
                        unit: summary.overallMedian == nil ? nil : "s",
                        tint: summary.quality?.color
                    )
                    statTile(
                        String(localized: "Success rate"),
                        value: summary.successRate.map { "\(Int(($0 * 100).rounded()))" } ?? "—",
                        unit: summary.successRate == nil ? nil : "%",
                        tint: nil
                    )
                    statTile(
                        String(localized: "Fastest"),
                        value: summary.fastest.map { displayName($0.target) } ?? "—",
                        unit: summary.fastest.map { "\(LatencyFormat.seconds($0.median)) s" },
                        tint: nil
                    )
                }

                HStack(spacing: 12) {
                    startButton
                    if let date = model.startedAt {
                        Text("\(String(localized: "Test started")) · \(date.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(heroBackground)
    }

    private var heroBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let tint = summary.quality.map { model.phase == .completed ? $0.color : accent } ?? accent
        return shape
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.025))
            .overlay(
                // 仪表背后的柔光随结论颜色变化。
                RadialGradient(
                    colors: [tint.opacity(colorScheme == .dark ? 0.26 : 0.16), tint.opacity(0)],
                    center: UnitPoint(x: 0.14, y: 0.5),
                    startRadius: 10,
                    endRadius: 260
                )
                .clipShape(shape)
            )
            .overlay(shape.strokeBorder(tint.opacity(0.18), lineWidth: 1))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: model.phase)
    }

    private func statTile(_ title: String, value: String, unit: String?, tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(tint ?? .primary)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.55 : 0.85))
        )
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: value)
        .accessibilityElement(children: .combine)
    }

    private var startButton: some View {
        Button {
            if model.isRunning {
                model.stop()
            } else {
                let addresses: IPAddressSet
                if case .online(let info) = environment.networkViewModel.status {
                    addresses = info.addresses
                } else {
                    addresses = .init(ipv4: nil, ipv6: nil)
                }
                model.start(httpAddresses: addresses)
            }
        } label: {
            Label {
                Text(startButtonTitle)
                    .contentTransition(.opacity)
            } icon: {
                Image(systemName: model.isRunning ? "stop.fill" : (model.startedAt == nil ? "play.fill" : "arrow.clockwise"))
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            }
            .frame(minWidth: 108)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(model.isRunning ? StatusPalette.stale : accent)
        .keyboardShortcut(.return, modifiers: .command)
        .help(model.isRunning ? String(localized: "Stop test") : String(localized: "Start test"))
        .accessibilityIdentifier("network-test.start")
    }

    private var startButtonTitle: String {
        if model.isRunning { return String(localized: "Stop test") }
        return model.startedAt == nil ? String(localized: "Start test") : String(localized: "Run again")
    }

    private var invalidatedBanner: some View {
        Label(
            String(localized: "Network changed. These results are outdated; run a new test."),
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.callout.weight(.medium))
        .foregroundStyle(StatusPalette.confirming)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StatusPalette.confirming.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("network-test.invalidated")
    }

    // MARK: 站点

    /// 站点与对比合为一个区块：每个站点一行，中间是共用刻度的时间轴。
    private var sitesSection: some View {
        let upper = max(300, (model.results.flatMap(\.successful).max() ?? 0) * 1.15)
        let hasData = model.results.contains { !$0.successful.isEmpty }
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle(String(localized: "Sites"), systemImage: "globe")
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.results) { result in
                    NetworkTestSiteRow(
                        result: result,
                        name: displayName(result.target),
                        upperBound: upper,
                        isSelected: model.selectedTargetID == result.id,
                        isActive: model.activeTargets.contains(result.id),
                        isExpanded: expandedTargets.contains(result.id),
                        accent: accent,
                        onSelect: {
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
                                model.selectedTargetID = result.id
                            }
                        },
                        onToggleDetails: {
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                                if expandedTargets.contains(result.id) {
                                    expandedTargets.remove(result.id)
                                } else {
                                    expandedTargets.insert(result.id)
                                }
                            }
                        }
                    )
                }
                NetworkTestComparisonAxis(upperBound: upper)
                    .padding(.top, 4)
                Text(
                    hasData || model.isRunning
                        ? String(localized: "Bars span the lowest to highest response; dots mark the median.")
                        : String(localized: "Run a test to compare sites.")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.035))
            )
            .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: upper)
        }
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.cardTitle)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    // MARK: WebRTC

    private var webRTCStatus: some View {
        Label {
            Text("WebRTC · \(webRTCLabel)")
                .contentTransition(reduceMotion ? .identity : .opacity)
        } icon: {
            Image(systemName: webRTCSymbol)
                .symbolEffect(.pulse, isActive: model.webRTCRunning && !reduceMotion)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace, options: .nonRepeating))
                .accessibilityHidden(true)
        }
        .tagCapsule(webRTCColor)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: webRTCLabel)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("network-test.webrtc-status")
        .help(String(localized: "WebRTC compares this app's observed exits only. Matching exits do not guarantee privacy in other browsers; missing public candidates or a comparable exit means the result is unknown."))
    }

    private var webRTCLabel: String {
        if model.phase == .invalidated { return String(localized: "Test again") }
        if model.webRTCRunning { return String(localized: "Checking…") }
        guard let report = model.webRTC else { return String(localized: "Not tested") }
        switch report.outcome {
        case .cancelled: return String(localized: "Stopped")
        case .unavailable: return String(localized: "Check unavailable")
        case .timedOut: return String(localized: "Check timed out")
        case .complete:
            switch report.assessment(httpAddresses: model.httpAddresses) {
            case .differentPath: return String(localized: "Exits differ")
            case .matchesObservedExit: return String(localized: "Exits match")
            case .inconclusive: return String(localized: "Unable to determine")
            }
        }
    }

    private var webRTCColor: Color {
        if model.webRTCRunning { return accent }
        guard let report = model.webRTC, model.phase != .invalidated else { return .secondary }
        switch report.assessment(httpAddresses: model.httpAddresses) {
        case .differentPath: return StatusPalette.confirming
        case .matchesObservedExit: return StatusPalette.online
        case .inconclusive: return .secondary
        }
    }

    private var webRTCSymbol: String {
        if model.webRTCRunning { return "dot.radiowaves.left.and.right" }
        if model.phase == .invalidated { return "arrow.clockwise" }
        guard let report = model.webRTC else { return "minus.circle" }
        switch report.assessment(httpAddresses: model.httpAddresses) {
        case .matchesObservedExit: return "checkmark.circle.fill"
        case .differentPath: return "exclamationmark.circle.fill"
        case .inconclusive: return "questionmark.circle"
        }
    }

    private var phaseLabel: String {
        switch model.phase {
        case .idle: String(localized: "Ready")
        case .running: model.progress == 1 ? String(localized: "Checking WebRTC") : String(localized: "Testing…")
        case .completed: String(localized: "Completed")
        case .cancelled: String(localized: "Stopped")
        case .invalidated: String(localized: "Outdated result")
        }
    }

    private func displayName(_ target: NetworkTestTarget) -> String {
        target.id == "baidu" ? String(localized: "Baidu") : target.name
    }
}

extension NetworkTestQuality {
    var color: Color {
        switch self {
        case .excellent, .good: StatusPalette.online
        case .fair: StatusPalette.confirming
        case .poor: StatusPalette.stale
        case .failed: StatusPalette.offline
        }
    }
}

// MARK: - 仪表

/// 分段进度环：每一段对应一次采样，逐段填满；完成后环色平滑过渡为结论颜色。
private struct NetworkTestDial: View {
    let phase: NetworkTestViewModel.Phase
    let completed: Int
    let total: Int
    let summary: NetworkTestSummary
    let phaseLabel: String
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRunning: Bool { phase == .running }
    private var ringColor: Color {
        phase == .completed ? (summary.quality?.color ?? accent) : accent
    }
    private let lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            segmentedRing
            centerContent
                .id(phase == .completed)
                .transition(.opacity)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: phase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(phaseLabel) · \(completed)/\(total)")
        .accessibilityIdentifier("network-test.phase.\(phase.rawValue)")
    }

    private var segmentedRing: some View {
        let count = max(total, 1)
        let gap = 0.022
        return ZStack {
            ForEach(0..<count, id: \.self) { index in
                let start = Double(index) / Double(count) + gap / 2
                let end = Double(index + 1) / Double(count) - gap / 2
                let filled = index < completed
                Circle()
                    .trim(from: start, to: end)
                    .stroke(
                        filled ? ringColor : ringColor.opacity(0.14),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(filled || reduceMotion ? 1 : 0.985)
                    .animation(
                        reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.35),
                        value: filled
                    )
            }
        }
        .padding(lineWidth / 2)
        .shadow(color: phase == .completed ? ringColor.opacity(0.35) : .clear, radius: 10)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: phase)
    }

    @ViewBuilder
    private var centerContent: some View {
        if phase == .completed, let quality = summary.quality {
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(LatencyFormat.seconds(summary.overallMedian))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if summary.overallMedian != nil {
                        Text("s").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                    }
                }
                Label(quality.label, systemImage: quality <= .good ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(quality.color)
                Text("\(completed)/\(total)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else if isRunning {
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(completed)")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(completed)))
                        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: completed)
                    Text("/\(total)")
                        .font(.callout.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(phaseLabel)
                    .font(.caption)
                    .foregroundStyle(accent)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: idleSymbol)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(accent)
                Text(phaseLabel)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                if completed > 0 {
                    Text("\(completed)/\(total)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var idleSymbol: String {
        switch phase {
        case .cancelled: "pause.circle"
        case .invalidated: "exclamationmark.arrow.circlepath"
        default: "gauge.with.dots.needle.33percent"
        }
    }
}

// MARK: - 对比图

/// 刻度换算：毫秒值映射到 0…1 的横向位置。
private enum ComparisonScale {
    static func position(_ milliseconds: Double, upperBound: Double) -> CGFloat {
        CGFloat(min(1, max(0, milliseconds / max(upperBound, 1))))
    }

    /// 取 0.1 s 的整数倍作为刻度，最多 5 个。
    static func ticks(upperBound: Double) -> [Double] {
        let seconds = upperBound / 1_000
        let step = seconds <= 0.5 ? 0.1 : (seconds <= 1.2 ? 0.25 : 0.5)
        return stride(from: 0, through: seconds, by: step).map { $0 * 1_000 }
    }
}

/// 站点行各列宽度；刻度行用同一组宽度，时间轴在每行都对齐。
private enum SiteRowMetrics {
    static let spacing: CGFloat = 10
    static let icon: CGFloat = 24
    static let name: CGFloat = 70
    static let value: CGFloat = 56
    static let quality: CGFloat = 50
    static let chevron: CGFloat = 20
    static let horizontalPadding: CGFloat = 8
    /// 行内容左边缘到时间轴起点的距离。
    static var trackLeading: CGFloat { icon + spacing + name + spacing }
}

private struct NetworkTestSiteRow: View {
    let result: NetworkTestResult
    let name: String
    let upperBound: Double
    let isSelected: Bool
    let isActive: Bool
    let isExpanded: Bool
    let accent: Color
    let onSelect: () -> Void
    let onToggleDetails: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: SiteRowMetrics.spacing) {
                icon
                Text(name)
                    .font(.callout.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .frame(width: SiteRowMetrics.name, alignment: .leading)
                NetworkTestSiteTrack(
                    result: result,
                    upperBound: upperBound,
                    isSelected: isSelected,
                    isActive: isActive,
                    accent: accent
                )
                .frame(height: 22)
                Text(result.median.map { "\(LatencyFormat.seconds($0)) s" } ?? "—")
                    .font(.callout.monospacedDigit().weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(result.median == nil ? .secondary : .primary)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .frame(width: SiteRowMetrics.value, alignment: .trailing)
                qualityLabel
                    .frame(width: SiteRowMetrics.quality, alignment: .leading)
                Button(action: onToggleDetails) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isExpanded ? accent : .secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: SiteRowMetrics.chevron, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Sample details"))
                .accessibilityLabel(String(localized: "Sample details"))
                .accessibilityIdentifier("network-test.details.\(result.id)")
            }
            if isExpanded {
                details
                    .padding(.leading, SiteRowMetrics.trackLeading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if !result.samples.isEmpty, result.successful.isEmpty, let failure = result.samples.last?.failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(StatusPalette.confirming)
                    .lineLimit(1)
                    .padding(.leading, SiteRowMetrics.trackLeading)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, SiteRowMetrics.horizontalPadding)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? accent.opacity(0.09) : Color.primary.opacity(isHovered ? 0.04 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: result)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
        .accessibilityValue(result.median.map { "\(LatencyFormat.seconds($0)) s" } ?? "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: Text(String(localized: "Select"))) { onSelect() }
    }

    private var icon: some View {
        Image("NetworkTest-\(result.target.id)")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: 16, height: 16)
            .frame(width: SiteRowMetrics.icon, height: SiteRowMetrics.icon)
            .background(.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var qualityLabel: some View {
        if let quality = result.quality {
            Text(quality.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(quality.color)
                .lineLimit(1)
                .transition(.opacity)
        } else {
            Text(isActive ? String(localized: "Testing…") : String(localized: "Waiting"))
                .font(.caption)
                .foregroundStyle(isActive ? accent : .secondary)
                .lineLimit(1)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            if result.samples.isEmpty {
                Text(String(localized: "Waiting for samples"))
                    .foregroundStyle(.secondary)
            }
            ForEach(result.samples) { sample in
                HStack(spacing: 8) {
                    Text(verbatim: "#\(sample.round)")
                        .frame(width: 22, alignment: .leading)
                        .foregroundStyle(.tertiary)
                    Text("\(LatencyFormat.seconds(sample.milliseconds)) s")
                        .frame(width: 52, alignment: .trailing)
                    if let code = sample.statusCode {
                        Text(verbatim: "HTTP \(code)")
                            .foregroundStyle(.secondary)
                    }
                    Text(sample.failure ?? String(localized: "Response accepted"))
                        .foregroundStyle(sample.succeeded ? Color.secondary : StatusPalette.confirming)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.bottom, 2)
    }
}

/// 一个站点的时间轴：浅色条为最快到最慢，圆点为中位数，小点为每次采样落点。
/// 正在请求时，一个光点沿轴发出再返回，像一次往返的探测包；返回后采样点落在对应耗时的位置。
private struct NetworkTestSiteTrack: View {
    let result: NetworkTestResult
    let upperBound: Double
    let isSelected: Bool
    let isActive: Bool
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color { (result.quality ?? .good).color }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 4)

                if let low = result.successful.min(), let high = result.successful.max() {
                    let start = position(low) * width
                    let end = position(high) * width
                    Capsule()
                        .fill(color.opacity(isSelected ? 0.4 : 0.26))
                        .frame(width: max(end - start, 8), height: 8)
                        .offset(x: min(start, width - 8))
                }

                ForEach(result.samples) { sample in
                    sampleMark(sample, width: width)
                        .transition(
                            reduceMotion ? .opacity : .scale(scale: 2.6).combined(with: .opacity)
                        )
                }

                if let median = result.median {
                    let size: CGFloat = isSelected ? 14 : 11
                    Circle()
                        .fill(color)
                        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
                        .frame(width: size, height: size)
                        .offset(x: position(median) * width - size / 2)
                }

                if isActive {
                    pulse(width: width)
                        .transition(.opacity)
                }
            }
            .frame(width: width, height: proxy.size.height, alignment: .leading)
        }
    }

    private func position(_ milliseconds: Double) -> CGFloat {
        ComparisonScale.position(milliseconds, upperBound: upperBound)
    }

    @ViewBuilder
    private func sampleMark(_ sample: NetworkTestSample, width: CGFloat) -> some View {
        if sample.succeeded, let value = sample.milliseconds {
            Circle()
                .fill(NetworkTestQuality(milliseconds: value).color.opacity(0.75))
                .frame(width: 6, height: 6)
                .offset(x: position(value) * width - 3)
        } else {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(StatusPalette.offline)
                .frame(width: 10, height: 10)
                .offset(x: width - 10)
        }
    }

    /// 往返光点：前半程减速飞出，后半程加速返回，带两颗渐隐的拖尾。
    private func pulse(width: CGFloat) -> some View {
        let reach = min(0.95, max(0.3, result.median.map(position) ?? 0.55))
        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .leading) {
                ForEach(0..<3, id: \.self) { index in
                    let x = reduceMotion
                        ? 0
                        : Self.pulseProgress(time - Double(index) * 0.045) * reach * width
                    Circle()
                        .fill(accent.opacity(index == 0 ? 1 : 0.45 / Double(index)))
                        .frame(width: index == 0 ? 8 : 6, height: index == 0 ? 8 : 6)
                        .shadow(color: index == 0 ? accent.opacity(0.6) : .clear, radius: 4)
                        .offset(x: x - (index == 0 ? 4 : 3))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// 1.2 秒一个往返：0 → 1 → 0。
    static func pulseProgress(_ time: TimeInterval) -> Double {
        let period = 1.2
        let phase = (time.truncatingRemainder(dividingBy: period) + period)
            .truncatingRemainder(dividingBy: period) / period
        if phase < 0.5 {
            let t = phase * 2
            return 1 - (1 - t) * (1 - t)
        } else {
            let t = (phase - 0.5) * 2
            return 1 - t * t
        }
    }
}

private struct NetworkTestComparisonAxis: View {
    let upperBound: Double

    var body: some View {
        HStack(spacing: SiteRowMetrics.spacing) {
            Color.clear.frame(width: SiteRowMetrics.icon, height: 1)
            Color.clear.frame(width: SiteRowMetrics.name, height: 1)
            GeometryReader { proxy in
                ForEach(ComparisonScale.ticks(upperBound: upperBound), id: \.self) { tick in
                    let x = ComparisonScale.position(tick, upperBound: upperBound) * proxy.size.width
                    Text(String(format: "%.1f s", tick / 1_000))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .position(x: x, y: proxy.size.height / 2)
                }
            }
            .frame(height: 14)
            Color.clear.frame(width: SiteRowMetrics.value, height: 1)
            Color.clear.frame(width: SiteRowMetrics.quality, height: 1)
            Color.clear.frame(width: SiteRowMetrics.chevron, height: 1)
        }
        .padding(.horizontal, SiteRowMetrics.horizontalPadding)
        .accessibilityHidden(true)
    }
}
