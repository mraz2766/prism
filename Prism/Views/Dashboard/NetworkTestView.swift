import SwiftUI
import Charts

struct NetworkTestView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedTargets: Set<String> = []

    private var model: NetworkTestViewModel { environment.networkTestViewModel }
    private var accent: Color { environment.settings.accentColorChoice.color }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if model.phase == .invalidated {
                    Label(String(localized: "Network changed. These results are outdated; run a new test."), systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(StatusPalette.confirming)
                        .accessibilityIdentifier("network-test.invalidated")
                }
                measurement
                targetList
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.phase)
        .accessibilityIdentifier("network-test.page")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(String(localized: "Network Test")).font(.title2.bold())
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            Text(String(localized: "Response time · stability"))
                                .font(.callout).foregroundStyle(.secondary)
                            Divider().frame(height: 12)
                            webRTCStatus
                        }
                        webRTCStatus
                    }
                }
                Spacer()
                Button {
                    if model.isRunning { model.stop() }
                    else {
                        let addresses: IPAddressSet
                        if case .online(let info) = environment.networkViewModel.status { addresses = info.addresses }
                        else { addresses = .init(ipv4: nil, ipv6: nil) }
                        model.start(httpAddresses: addresses)
                    }
                } label: {
                    Label(model.isRunning ? String(localized: "Stop test") : String(localized: "Start test"),
                          systemImage: model.isRunning ? "stop.fill" : "play.fill")
                        .frame(minWidth: 96)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("network-test.start")
            }
            Text(String(localized: "Three samples per site. No bandwidth test."))
                .font(.caption).foregroundStyle(.secondary)
            if let date = model.startedAt {
                Text("\(String(localized: "Test started")) · \(date.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var measurement: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    siteIcon(model.selectedResult.target)
                    Text(displayName(model.selectedResult.target)).font(.headline)
                    Text(String(localized: "Median")).font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(LatencyFormat.seconds(model.selectedResult.median))
                        .font(.system(size: 48, weight: .light, design: .rounded)).monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: model.selectedResult.median)
                    Text("s").font(.headline).foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    metric(String(localized: "Lowest"), value: model.selectedResult.successful.min())
                    metric(String(localized: "Highest"), value: model.selectedResult.successful.max())
                    metric(String(localized: "Range"), value: model.selectedResult.spread)
                }
            }
            .frame(minWidth: 190, alignment: .leading)
            VStack(spacing: 10) {
                sampleChart
                HStack {
                    Text("\(String(localized: "Actual samples")) · s")
                    Spacer()
                    Text("\(model.selectedResult.samples.count)/\(NetworkTestViewModel.sampleCount)")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            progressRing
        }
        .padding(.vertical, 8)
    }

    private func metric(_ label: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(LatencyFormat.seconds(value)).font(.callout.monospacedDigit())
        }
    }

    private var progressRing: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(accent.opacity(0.12), lineWidth: 5)
                Circle().trim(from: 0, to: model.progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: model.progress)
                VStack(spacing: 3) {
                    Image(systemName: model.phase == .completed ? "checkmark" : "waveform.path")
                        .font(.title3).foregroundStyle(accent)
                        .symbolEffect(.pulse, isActive: model.isRunning && !reduceMotion)
                    Text("\(model.completedSamples)/\(model.totalSamples)").font(.caption2.monospacedDigit())
                }
            }
            .frame(width: 70, height: 70)
            Text(phaseLabel).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 88)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(phaseLabel) · \(model.completedSamples)/\(model.totalSamples)")
        .accessibilityIdentifier("network-test.phase.\(model.phase.rawValue)")
    }

    private var sampleChart: some View {
        Chart {
            ForEach(chartPoints) { point in
                LineMark(x: .value("Sample", point.round), y: .value("s", point.value), series: .value("Segment", point.segment))
                    .foregroundStyle(accent).lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Sample", point.round), y: .value("s", point.value))
                    .foregroundStyle(accent).symbolSize(28)
            }
        }
        .chartXScale(domain: 0.8...(Double(NetworkTestViewModel.sampleCount) + 0.2))
        .chartYScale(domain: 0...max(0.1, (model.selectedResult.successful.max() ?? 0) / 1_000 * 1.2))
        .chartXAxis { AxisMarks(values: Array(1...NetworkTestViewModel.sampleCount)) }
        .chartYAxis { AxisMarks(position: .leading) }
        .chartLegend(.hidden)
        .frame(height: 118)
        .overlay {
            if chartPoints.isEmpty {
                Text(String(localized: "Waiting for samples")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.selectedResult)
        .accessibilityLabel(String(localized: "Successful response times in seconds"))
    }

    private struct ChartPoint: Identifiable {
        let round: Int
        let value: Double
        let segment: Int
        var id: Int { round }
    }

    private var chartPoints: [ChartPoint] {
        var segment = 0
        return model.selectedResult.samples.compactMap { sample in
            guard sample.succeeded, let value = sample.milliseconds else { segment += 1; return nil }
            return ChartPoint(round: sample.round, value: value / 1_000, segment: segment)
        }
    }

    private var targetList: some View {
        VStack(spacing: 0) {
            ForEach(model.results) { result in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Button { model.selectedTargetID = result.id } label: {
                            HStack(spacing: 10) {
                                siteIcon(result.target)
                                    .overlay(alignment: .bottomTrailing) {
                                        if model.activeTargets.contains(result.id) {
                                            Image(systemName: "circle.fill")
                                                .font(.system(size: 6))
                                                .foregroundStyle(accent)
                                                .symbolEffect(.pulse, isActive: !reduceMotion)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(displayName(result.target)).font(.callout.weight(.medium))
                                    Text(result.target.url.host ?? "").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(displayName(result.target))
                        .accessibilityAddTraits(model.selectedTargetID == result.id ? .isSelected : [])
                        HStack(spacing: 4) {
                            ForEach(1...NetworkTestViewModel.sampleCount, id: \.self) { round in
                                Capsule().fill(sampleColor(result.samples.first { $0.round == round }))
                                    .frame(width: 12, height: 5)
                            }
                        }
                        .accessibilityHidden(true)
                        Text("\(result.successful.count)/\(result.samples.count)")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 32)
                            .help(String(localized: "Successful / completed requests"))
                        Text("\(LatencyFormat.seconds(result.median)) s")
                            .font(.callout.monospacedDigit()).frame(width: 76, alignment: .trailing)
                            .contentTransition(reduceMotion ? .identity : .numericText())
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                if expandedTargets.contains(result.id) { expandedTargets.remove(result.id) }
                                else { expandedTargets.insert(result.id) }
                            }
                        } label: {
                            Image(systemName: "chevron.right").rotationEffect(.degrees(expandedTargets.contains(result.id) ? 90 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Sample details"))
                        .accessibilityIdentifier("network-test.details.\(result.id)")
                    }
                    .padding(.vertical, 12)
                    if expandedTargets.contains(result.id) {
                        sampleDetails(result)
                            .padding(.bottom, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if let failure = result.samples.last?.failure {
                        Text(failure).font(.caption).foregroundStyle(StatusPalette.confirming).padding(.bottom, 8)
                    }
                    if result.id != model.results.last?.id { Divider() }
                }
                .padding(.horizontal, 12)
                .background(model.selectedTargetID == result.id ? accent.opacity(0.055) : .clear)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func sampleDetails(_ result: NetworkTestResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if result.samples.isEmpty { Text(String(localized: "Waiting for samples")) }
            ForEach(result.samples) { sample in
                HStack {
                    Text("#\(sample.round)").frame(width: 26, alignment: .leading)
                    Text("\(LatencyFormat.seconds(sample.milliseconds)) s").frame(width: 70, alignment: .trailing)
                    if let code = sample.statusCode { Text("HTTP \(code)") }
                    Spacer()
                    Text(sample.failure ?? String(localized: "Response accepted"))
                        .foregroundStyle(sample.succeeded ? Color.secondary : StatusPalette.confirming)
                }
            }
        }
        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
    }

    private var webRTCStatus: some View {
        HStack(spacing: 5) {
            Text("WebRTC").foregroundStyle(.secondary)
            Image(systemName: webRTCSymbol)
                .symbolEffect(.pulse, isActive: model.webRTCRunning && !reduceMotion)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace, options: .nonRepeating))
                .accessibilityHidden(true)
            Text(webRTCLabel)
                .contentTransition(reduceMotion ? .identity : .opacity)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(webRTCColor)
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

    private func sampleColor(_ sample: NetworkTestSample?) -> Color {
        guard let sample else { return Color.primary.opacity(0.1) }
        return sample.succeeded ? accent : StatusPalette.confirming
    }

    private func displayName(_ target: NetworkTestTarget) -> String { target.id == "baidu" ? String(localized: "Baidu") : target.name }

    private func siteIcon(_ target: NetworkTestTarget) -> some View {
        Image("NetworkTest-\(target.id)")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: 22, height: 22)
            .padding(3)
            .background(.white, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
    }
}
