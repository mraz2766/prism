import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var status: NetworkStatus { environment.networkViewModel.status }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let info = status.info {
                CountryHeroView(
                    info: info,
                    status: status,
                    flagStyle: environment.settings.countryFlagStyle,
                    cityOverride: environment.cityLocalizer.displayCity(for: info),
                    compact: true,
                    showsRoute: false,
                    outsideExpectedRegion: environment.isOutsideExpectedRegion
                )
                SectionCard(horizontalPadding: 14, verticalPadding: 12) {
                    addressRows(for: info)
                }
            } else {
                unavailableContent
                if !status.isOffline {
                    SectionCard(horizontalPadding: 14, verticalPadding: 12) {
                        domesticIPv4Row(currentIPv4: nil)
                    }
                }
            }
            footer
        }
        .padding(14)
        .frame(width: 360)
        .tint(environment.settings.accentColorChoice.color)
        .onExitCommand {
            NotificationCenter.default.post(name: .prismClosePopover, object: nil)
        }
    }

    @ViewBuilder
    private func addressRows(for info: NetworkInfo) -> some View {
        let ipv4 = info.addresses.ipv4
        let domesticMatches = environment.domesticIPv4ViewModel.status.matchesCurrentExit(ipv4)
        VStack(spacing: 12) {
            if let ipv4 {
                IPAddressRow(
                    label: String(localized: "Public IPv4"),
                    address: ipv4,
                    detail: domesticMatches ? String(localized: "Domestic exit matches") : nil,
                    accessibilityIdentifier: "popover.ipv4-row"
                )
            } else {
                IPAddressRow(
                    label: String(localized: "Public IPv6"),
                    address: info.addresses.ipv6,
                    accessibilityIdentifier: "popover.ipv6-row"
                )
            }
            if !domesticMatches {
                Divider().transition(.opacity)
                domesticIPv4Row(currentIPv4: ipv4)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
            if NetworkSummaryRow.hasContent(info) {
                Divider().transition(.opacity)
                NetworkSummaryRow(info: info)
                    .transition(.opacity)
            }
        }
        // 两行与合并一行之间平滑过渡，弹窗高度不再硬跳。
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: domesticMatches)
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: NetworkSummaryRow.hasContent(info))
    }

    private var unavailableContent: some View {
        VStack(spacing: 8) {
            if status.isRefreshing || status == .idle {
                ProgressView()
                    .controlSize(.regular)
                    .frame(height: 30)
            } else {
                Image(systemName: status.symbolName)
                    .font(.system(size: 28))
                    .foregroundStyle(status.isOffline ? AnyShapeStyle(StatusPalette.offline) : AnyShapeStyle(.secondary))
                    .frame(height: 30)
            }
            Text(status.shortLabel).font(.headline)
            Group {
                if case .failed(let reason) = status {
                    Text(reason.userDescription)
                } else if status.isOffline {
                    Text(String(localized: "No internet connection"))
                } else {
                    Text(String(localized: "Checking your current network exit…"))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        // 与有数据时的主卡片区域高度接近，状态切换时弹窗不会大幅伸缩。
        .frame(minHeight: 118)
        .accessibilityElement(children: .combine)
    }

    /// 元数据更新在后台完成，底栏只呈现出口确认状态。
    private var footerStatusKind: Int {
        switch status {
        case .verifying: 1
        case .stale: 2
        default: 0
        }
    }

    @ViewBuilder
    private var footerStatus: some View {
        switch status {
        case .verifying(_, let candidateAddress):
            Label {
                Text("\(String(localized: "Confirming new exit")) · \(candidateAddress)")
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(StatusPalette.confirming)
            .accessibilityLabel(String(localized: "Confirming new exit"))
            .transition(.opacity)
        case .stale(let info, _):
            Text("\(String(localized: "Last confirmed")) · \(info.checkedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(StatusPalette.stale)
                .lineLimit(1)
                .transition(.opacity)
        default:
            if let info = status.info {
                HStack(spacing: 8) {
                    ConfirmedTimeText(date: info.checkedAt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let latency = environment.latencyModel.milliseconds,
                       info.exitSource != .domesticFallback {
                        LatencyLabel(milliseconds: latency)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .center) {
            footerStatus
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: footerStatusKind)
            Spacer(minLength: 8)

            PopoverActionButton(
                systemName: "arrow.clockwise",
                help: String(localized: "Refresh"),
                shortcutKey: "r",
                isSpinning: status.isRefreshing,
                isDisabled: status.isRefreshing
            ) {
                environment.refreshCoordinator.triggerManual()
            }

            PopoverActionButton(
                systemName: "macwindow",
                help: String(localized: "Open Details"),
                shortcutKey: "o"
            ) {
                closeThen { environment.showDashboard(.overview) }
            }

            PopoverActionButton(
                systemName: "gearshape",
                help: String(localized: "Settings"),
                shortcutKey: ","
            ) {
                closeThen { environment.openSettings() }
            }
        }
    }

    private func closeThen(_ action: @escaping @MainActor () -> Void) {
        NotificationCenter.default.post(name: .prismClosePopover, object: nil)
        Task { @MainActor in
            await Task.yield()
            action()
        }
    }

    private func domesticIPv4Row(currentIPv4: String?) -> some View {
        let domesticStatus = environment.domesticIPv4ViewModel.status
        return IPAddressRow(
            label: String(localized: "Domestic exit IPv4"),
            address: domesticStatus.info?.address,
            detail: domesticStatus.detailLabel(currentIPv4: currentIPv4),
            placeholder: domesticStatus.isLoading || domesticStatus == .idle
                ? String(localized: "Detecting")
                : nil,
            accessibilityIdentifier: "popover.domestic-ipv4-row"
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: domesticStatus)
    }
}

extension DomesticIPv4Status {
    /// 国内出口行的补充说明：与当前出口的关系，或检测进度。
    func detailLabel(currentIPv4: String?) -> String? {
        switch self {
        case .idle:
            nil
        case .loading(let previous):
            previous == nil ? nil : String(localized: "Detecting")
        case .available(let info):
            info.relationship(to: currentIPv4).label
        case .failed(let previous, _):
            previous == nil ? nil : String(localized: "Last known result")
        }
    }
}

private struct PopoverActionButton: View {
    let systemName: String
    let help: String
    var shortcutKey: KeyEquivalent?
    /// 非空时图标按刷新状态旋转。
    var isSpinning: Bool?
    var isDisabled = false
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Group {
                if let isSpinning {
                    RefreshGlyph(systemName: systemName, isActive: isSpinning)
                } else {
                    Image(systemName: systemName)
                }
            }
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(isHovered ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(PopoverActionButtonStyle(isHovered: isHovered))
        .disabled(isDisabled)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .help(help)
        .accessibilityLabel(help)
        .keyboardShortcutIfPresent(shortcutKey)
    }
}

private struct PopoverActionButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.tint.opacity(isHovered || configuration.isPressed ? 0.12 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private extension View {
    @ViewBuilder
    func keyboardShortcutIfPresent(_ key: KeyEquivalent?) -> some View {
        if let key {
            keyboardShortcut(key, modifiers: .command)
        } else {
            self
        }
    }
}

/// 刷新图标匀速旋转；刷新结束后转完当前这一圈再停，不会倒转回零。
struct RefreshGlyph: View {
    var systemName = "arrow.clockwise"
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?
    @State private var stopAt: Date?
    @State private var stopTask: Task<Void, Never>?
    private static let period: TimeInterval = 0.8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: startedAt == nil)) { context in
            Image(systemName: systemName)
                .rotationEffect(.degrees(Self.angle(at: context.date, startedAt: startedAt, stopAt: stopAt)))
        }
        .onAppear { update() }
        .onChange(of: isActive) { _, _ in update() }
        .onDisappear { stopTask?.cancel() }
    }

    static func angle(at date: Date, startedAt: Date?, stopAt: Date?) -> Double {
        guard let startedAt else { return 0 }
        if let stopAt, date >= stopAt { return 0 }
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        return (elapsed / period).truncatingRemainder(dividingBy: 1) * 360
    }

    /// 当前这一圈结束的时刻。
    static func completionDate(startedAt: Date, now: Date) -> Date {
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        let revolutions = max(1, (elapsed / period).rounded(.up))
        return startedAt.addingTimeInterval(revolutions * period)
    }

    private func update() {
        stopTask?.cancel()
        stopTask = nil
        if isActive && !reduceMotion {
            stopAt = nil
            if startedAt == nil { startedAt = .now }
        } else if let startedAt {
            let end = Self.completionDate(startedAt: startedAt, now: .now)
            stopAt = end
            stopTask = Task { @MainActor in
                let delay = max(0, end.timeIntervalSinceNow)
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                self.startedAt = nil
                self.stopAt = nil
            }
        }
    }
}
