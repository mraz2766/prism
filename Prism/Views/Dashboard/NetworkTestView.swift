import SwiftUI

/// 网络测试页：顶部仪表给出整体结论，下方站点卡片展示每轮采样，最后用区间图横向对比各站点。
struct NetworkTestView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var expandedTargets: Set<String> = []
    @State private var appeared = false

    private var model: NetworkTestViewModel { environment.networkTestViewModel }
    private var accent: Color { environment.settings.accentColorChoice.color }
    private var summary: NetworkTestSummary { NetworkTestSummary(results: model.results) }

    /// 所有站点共用的柱高刻度，卡片之间的柱子可以直接比较。
    private var barScale: Double {
        max(400, model.results.flatMap(\.successful).max() ?? 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if model.phase == .invalidated {
                    invalidatedBanner
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                sitesSection
                comparisonSection
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: model.phase)
        .onAppear {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.5)) { appeared = true }
        }
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
                accent: accent,
                completionTrigger: model.phase == .completed ? model.finishedAt : nil
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

    // MARK: 站点卡片

    private var sitesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(String(localized: "Sites"), systemImage: "globe")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                    NetworkTestSiteCard(
                        result: result,
                        name: displayName(result.target),
                        isSelected: model.selectedTargetID == result.id,
                        isActive: model.activeTargets.contains(result.id),
                        isExpanded: expandedTargets.contains(result.id),
                        barScale: barScale,
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
                    // 首次进入时卡片依次浮现。
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 14)
                    .animation(
                        reduceMotion ? nil : .smooth(duration: 0.45).delay(Double(index) * 0.06),
                        value: appeared
                    )
                }
            }
        }
    }

    // MARK: 对比图

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(String(localized: "Comparison"), systemImage: "chart.bar.xaxis")
            VStack(alignment: .leading, spacing: 8) {
                comparisonChart
                Text(String(localized: "Bars span the lowest to highest response; dots mark the median."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.035))
            )
        }
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .smooth(duration: 0.45).delay(0.3), value: appeared)
    }

    /// 自绘区间图：每个站点一行，浅色胶囊是最低到最高，圆点是中位数，选中站点加粗。
    private var comparisonChart: some View {
        let upper = max(300, (model.results.flatMap(\.successful).max() ?? 0) * 1.15)
        return VStack(spacing: 10) {
            ForEach(model.results) { result in
                NetworkTestComparisonRow(
                    result: result,
                    name: displayName(result.target),
                    upperBound: upper,
                    isSelected: result.id == model.selectedTargetID
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
                        model.selectedTargetID = result.id
                    }
                }
            }
            NetworkTestComparisonAxis(upperBound: upper)
        }
        .overlay {
            if model.results.allSatisfy({ $0.successful.isEmpty }) {
                Text(model.isRunning ? String(localized: "Waiting for samples") : String(localized: "Run a test to compare sites."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: model.results)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.selectedTargetID)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Successful response times in seconds"))
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

/// 分段进度环：每一段对应一次采样。测试中有雷达扫描与外扩波纹，完成时环色变为结论颜色并放出一圈光晕。
private struct NetworkTestDial: View {
    let phase: NetworkTestViewModel.Phase
    let completed: Int
    let total: Int
    let summary: NetworkTestSummary
    let phaseLabel: String
    let accent: Color
    let completionTrigger: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRunning: Bool { phase == .running }
    private var ringColor: Color {
        phase == .completed ? (summary.quality?.color ?? accent) : accent
    }
    private let lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            if isRunning && !reduceMotion {
                ripples
            }
            segmentedRing
            if isRunning && !reduceMotion {
                radarSweep
            }
            centerContent
                .id(phase == .completed)
                .transition(
                    reduceMotion ? .opacity : .scale(scale: 0.82).combined(with: .opacity)
                )
        }
        .keyframeAnimator(initialValue: 0.0, trigger: completionTrigger) { content, value in
            // 完成瞬间从环上向外扩散一圈光晕。
            content.overlay(
                Circle()
                    .stroke(ringColor, lineWidth: 3)
                    .scaleEffect(1 + value * 0.24)
                    .opacity(value == 0 || reduceMotion ? 0 : (1 - value) * 0.8)
            )
        } keyframes: { _ in
            LinearKeyframe(0.001, duration: 0.01)
            CubicKeyframe(1, duration: 0.75)
            LinearKeyframe(0, duration: 0.01)
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

    private var radarSweep: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 2.4) / 2.4 * 360
            Circle()
                .fill(
                    AngularGradient(
                        colors: [accent.opacity(0), accent.opacity(0), accent.opacity(0.28)],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(100)
                    )
                )
                .rotationEffect(.degrees(angle - 100))
                .padding(lineWidth + 8)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var ripples: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let progress = (time / 2.4 + Double(index) / 3)
                        .truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(accent.opacity((1 - progress) * 0.3), lineWidth: 1.5)
                        .scaleEffect(1 + progress * 0.2)
                }
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
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
                    .symbolEffect(.bounce, value: completionTrigger)
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

// MARK: - 站点卡片

private struct NetworkTestSiteCard: View {
    let result: NetworkTestResult
    let name: String
    let isSelected: Bool
    let isActive: Bool
    let isExpanded: Bool
    let barScale: Double
    let accent: Color
    let onSelect: () -> Void
    let onToggleDetails: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            NetworkTestSampleBars(
                samples: result.samples,
                isActive: isActive,
                scale: barScale,
                accent: accent
            )
            footer
            if isExpanded {
                Divider()
                details
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let failure = result.samples.last?.failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(StatusPalette.confirming)
                    .lineLimit(2)
                    .transition(.opacity)
            }
        }
        .padding(14)
        .background(
            shape.fill(
                isSelected
                    ? accent.opacity(colorScheme == .dark ? 0.14 : 0.07)
                    : Color.primary.opacity(isHovered ? 0.06 : (colorScheme == .dark ? 0.045 : 0.03))
            )
        )
        .overlay(shape.strokeBorder(isSelected ? accent.opacity(0.7) : Color.clear, lineWidth: 1.5))
        .overlay { if isActive { activeBorder } }
        .contentShape(shape)
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { isHovered = hovering }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: result)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: Text(String(localized: "Select"))) { onSelect() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("NetworkTest-\(result.target.id)")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 20, height: 20)
                .padding(5)
                .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                Text(result.target.url.host ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(LatencyFormat.seconds(result.median))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                    Text("s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                qualityLabel
            }
        }
    }

    @ViewBuilder
    private var qualityLabel: some View {
        if let quality = result.quality {
            HStack(spacing: 4) {
                Circle().fill(quality.color).frame(width: 6, height: 6)
                Text(quality.label)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(quality.color)
            .transition(.opacity)
        } else {
            Text(isActive ? String(localized: "Testing…") : String(localized: "Waiting"))
                .font(.caption)
                .foregroundStyle(isActive ? accent : .secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("\(result.successful.count)/\(result.samples.count) \(String(localized: "successful"))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .help(String(localized: "Successful / completed requests"))
            if let spread = result.spread {
                Text("· \(String(localized: "Range")) \(LatencyFormat.seconds(spread)) s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onToggleDetails) {
                HStack(spacing: 3) {
                    Text(String(localized: "Details"))
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(isExpanded ? accent : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(isExpanded ? 0 : 0.05), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Sample details"))
            .accessibilityIdentifier("network-test.details.\(result.id)")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if result.samples.isEmpty {
                Text(String(localized: "Waiting for samples"))
            }
            ForEach(result.samples) { sample in
                HStack(spacing: 8) {
                    Text(verbatim: "#\(sample.round)")
                        .frame(width: 22, alignment: .leading)
                        .foregroundStyle(.tertiary)
                    Text("\(LatencyFormat.seconds(sample.milliseconds)) s")
                        .frame(width: 56, alignment: .trailing)
                    if let code = sample.statusCode {
                        Text(verbatim: "HTTP \(code)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(sample.failure ?? String(localized: "Response accepted"))
                        .foregroundStyle(sample.succeeded ? Color.secondary : StatusPalette.confirming)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .font(.caption.monospacedDigit())
    }

    /// 正在请求的站点：描边上有一道光沿着卡片边缘流动。
    private var activeBorder: some View {
        Group {
            if reduceMotion {
                shape.strokeBorder(accent.opacity(0.6), lineWidth: 1.5)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                    let angle = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1.6) / 1.6 * 360
                    shape.strokeBorder(
                        AngularGradient(
                            colors: [accent.opacity(0), accent.opacity(0.15), accent, accent.opacity(0.15), accent.opacity(0)],
                            center: .center,
                            angle: .degrees(angle)
                        ),
                        lineWidth: 2
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

// MARK: - 采样柱

/// 每轮采样一根柱子，高度按全局刻度换算；柱子到达时从底部弹起，正在请求的一轮显示呼吸占位。
private struct NetworkTestSampleBars: View {
    let samples: [NetworkTestSample]
    let isActive: Bool
    let scale: Double
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barAreaHeight: CGFloat = 44

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(1...NetworkTestViewModel.sampleCount, id: \.self) { round in
                column(round: round, sample: samples.first { $0.round == round })
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Successful response times in seconds"))
        .accessibilityValue(
            samples.map { $0.succeeded ? "\(LatencyFormat.seconds($0.milliseconds)) s" : String(localized: "Failed") }
                .joined(separator: ", ")
        )
    }

    private func column(round: Int, sample: NetworkTestSample?) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                if let sample {
                    bar(for: sample)
                        .transition(
                            reduceMotion ? .opacity : .scale(scale: 0.05, anchor: .bottom).combined(with: .opacity)
                        )
                } else if isActive && round == samples.count + 1 {
                    pendingBar
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: 30)
            .frame(height: barAreaHeight)
            .animation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.38), value: sample)

            Text(label(for: sample))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(sample?.succeeded == false ? AnyShapeStyle(StatusPalette.offline) : AnyShapeStyle(.tertiary))
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func bar(for sample: NetworkTestSample) -> some View {
        if sample.succeeded, let value = sample.milliseconds {
            let quality = NetworkTestQuality(milliseconds: value)
            let ratio = min(1, max(0.12, value / scale))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [quality.color.opacity(0.75), quality.color],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(height: barAreaHeight * ratio)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(StatusPalette.offline.opacity(0.18))
                .overlay(
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(StatusPalette.offline)
                )
        }
    }

    private var pendingBar: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let wave = (sin(context.date.timeIntervalSinceReferenceDate * 4) + 1) / 2
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(accent.opacity(reduceMotion ? 0.25 : 0.14 + wave * 0.22))
                .frame(height: barAreaHeight * (reduceMotion ? 0.4 : 0.3 + wave * 0.25))
        }
    }

    private func label(for sample: NetworkTestSample?) -> String {
        guard let sample else { return "—" }
        return sample.succeeded ? LatencyFormat.seconds(sample.milliseconds) : String(localized: "Failed")
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

private struct NetworkTestComparisonRow: View {
    let result: NetworkTestResult
    let name: String
    let upperBound: Double
    let isSelected: Bool

    private let labelWidth: CGFloat = 72
    private let valueWidth: CGFloat = 64

    var body: some View {
        let color = (result.quality ?? .good).color
        HStack(spacing: 10) {
            Text(name)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 4)
                    if let low = result.successful.min(), let high = result.successful.max() {
                        let start = ComparisonScale.position(low, upperBound: upperBound) * width
                        let end = ComparisonScale.position(high, upperBound: upperBound) * width
                        Capsule()
                            .fill(color.opacity(isSelected ? 0.45 : 0.28))
                            .frame(width: max(end - start, 8), height: isSelected ? 10 : 8)
                            .offset(x: min(start, width - 8))
                    }
                    if let median = result.median {
                        let x = ComparisonScale.position(median, upperBound: upperBound) * width
                        Circle()
                            .fill(color)
                            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
                            .frame(width: isSelected ? 16 : 12, height: isSelected ? 16 : 12)
                            .shadow(color: color.opacity(0.35), radius: isSelected ? 4 : 0)
                            .offset(x: x - (isSelected ? 8 : 6))
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 18)
            Text(result.median.map { "\(LatencyFormat.seconds($0)) s" } ?? "—")
                .font(.callout.monospacedDigit().weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .contentTransition(.numericText())
                .frame(width: valueWidth, alignment: .trailing)
        }
        .frame(height: 24)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct NetworkTestComparisonAxis: View {
    let upperBound: Double

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 72, height: 1)
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
            Color.clear.frame(width: 64, height: 1)
        }
        .accessibilityHidden(true)
    }
}
