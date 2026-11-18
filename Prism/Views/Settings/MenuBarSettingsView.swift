import SwiftUI

struct MenuBarSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var previewState: PreviewState = .online
    @State private var showsTemplateText = false

    private var reveal: Animation? { reduceMotion ? nil : .smooth(duration: 0.28) }

    var body: some View {
        @Bindable var settings = settings
        SettingsPage {
            SettingsGroup(title: String(localized: "Menu Bar Preview"), systemImage: "eye") {
                MenuBarMockup(
                    presentation: preview(status: previewState.status),
                    flagStyle: settings.countryFlagStyle
                )
                .padding(10)
                SettingsDivider()
                SettingsRow(title: String(localized: "Preview state")) {
                    Picker(String(localized: "Preview state"), selection: $previewState.animation(reveal)) {
                        ForEach(PreviewState.allCases) { state in
                            Text(state.label).tag(state)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .fixedSize()
                }
            }

            SettingsGroup(title: String(localized: "Display style"), systemImage: "text.alignleft") {
                SettingsRow(title: String(localized: "Menu bar shows")) {
                    Picker(String(localized: "Menu bar shows"), selection: $settings.menuBarDisplayMode.animation(reveal)) {
                        ForEach(MenuBarDisplayMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityIdentifier("settings.menuBar.displayMode")
                }
                if settings.menuBarDisplayMode == .custom {
                    customComposer
                        .transition(.settingsReveal)
                }
            }

            SettingsGroup(
                title: String(localized: "Country flag style"),
                systemImage: "flag",
                footer: String(localized: "Flag style also applies to the popover, details, and history. Each style uses a compact menu bar rendering.")
            ) {
                FlagStyleGrid(
                    selection: $settings.countryFlagStyle,
                    sampleCountryCode: sampleCountryCode
                )
                .padding(10)
            }
        }
    }

    // MARK: 自定义内容

    private var composition: MenuBarTemplateComposition {
        MenuBarTemplateComposition(template: settings.customMenuTemplate)
    }

    private func updateComposition(_ change: (inout MenuBarTemplateComposition) -> Void) {
        var next = composition
        change(&next)
        guard !next.isEmpty else { return }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.3)) {
            settings.customMenuTemplate = next.template
        }
    }

    private var customComposer: some View {
        @Bindable var settings = settings
        let current = composition
        let available = MenuBarTemplateElement.allCases.filter { !current.elements.contains($0) }

        return VStack(spacing: 0) {
            SettingsDivider()
            SettingsRow(title: String(localized: "Show flag")) {
                SettingsSwitch(title: String(localized: "Show flag"), isOn: Binding(
                    get: { current.showsFlag },
                    set: { newValue in updateComposition { $0.showsFlag = newValue } }
                ))
                .disabled(current.showsFlag && current.elements.isEmpty)
                .accessibilityIdentifier("settings.menuBar.custom.flag")
            }
            SettingsDivider()
            SettingsRow(title: String(localized: "Text"), subtitle: String(localized: "Drag to reorder")) {
                FlowLayout(spacing: 6, alignment: .trailing) {
                    if current.elements.isEmpty {
                        Text(String(localized: "None"))
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(Array(current.elements.enumerated()), id: \.element) { index, element in
                        selectedChip(element, index: index, in: current)
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
            }
            if !available.isEmpty {
                SettingsDivider()
                SettingsRow(title: String(localized: "Add")) {
                    FlowLayout(spacing: 6, alignment: .trailing) {
                        ForEach(available) { element in
                            addChip(element)
                                .transition(.scale(scale: 0.7).combined(with: .opacity))
                        }
                    }
                }
            }
            SettingsDivider()
            SettingsRow(title: String(localized: "Edit as text")) {
                Button {
                    withAnimation(reveal) { showsTemplateText.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(showsTemplateText ? 90 : 0))
                        .foregroundStyle(showsTemplateText ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Edit as text"))
            }
            if showsTemplateText {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(String(localized: "Custom template"), text: $settings.customMenuTemplate)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                    Text(String(localized: "Available placeholders: {flag} {code} {country} {city} {status}. The flag always appears first."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !MenuBarTemplateComposition.isRepresentable(settings.customMenuTemplate) {
                        Text(String(localized: "The template contains custom text. Editing the items above will replace it."))
                            .font(.caption)
                            .foregroundStyle(StatusPalette.confirming)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .transition(.settingsReveal)
            }
        }
    }

    private func selectedChip(
        _ element: MenuBarTemplateElement,
        index: Int,
        in current: MenuBarTemplateComposition
    ) -> some View {
        let canRemove = current.showsFlag || current.elements.count > 1
        return HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(element.label)
                .font(.callout)
            Button {
                updateComposition { $0.elements.remove(at: index) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canRemove)
            .opacity(canRemove ? 1 : 0.35)
            .help(String(localized: "Remove"))
            .accessibilityIdentifier("settings.menuBar.custom.remove.\(element.rawValue)")
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .background(.tint.opacity(0.14), in: Capsule())
        .contentShape(Capsule())
        .draggable(element.rawValue)
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first,
                  let dragged = MenuBarTemplateElement(rawValue: raw),
                  dragged != element else { return false }
            updateComposition { $0.move(dragged, before: element) }
            return true
        }
        .help(String(localized: "Drag to reorder"))
    }

    private func addChip(_ element: MenuBarTemplateElement) -> some View {
        Button {
            updateComposition { $0.elements.append(element) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text(element.label)
                    .font(.callout)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(.secondary)
            .overlay(
                Capsule().strokeBorder(
                    Color.secondary.opacity(0.45),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.menuBar.custom.add.\(element.rawValue)")
    }

    // MARK: 预览

    /// 预览用的国家：优先用当前出口，让用户看到的就是自己菜单栏上的那面旗。
    private var sampleCountryCode: String {
        let code = environment.networkViewModel.status.retainedInfo?.location.countryCode ?? ""
        return CountryFlag.normalizedCode(code) ?? "JP"
    }

    private func preview(status: NetworkStatus) -> MenuBarPresentation {
        MenuBarLabelRenderer.presentation(
            status: status,
            mode: settings.menuBarDisplayMode,
            flagStyle: settings.countryFlagStyle,
            customTemplate: settings.customMenuTemplate,
            cityOverride: status.info.flatMap { environment.cityLocalizer.displayCity(for: $0) }
        )
    }

    enum PreviewState: String, CaseIterable, Identifiable {
        case online
        case confirming
        case offline

        var id: String { rawValue }

        var label: String {
            switch self {
            case .online: String(localized: "Online")
            case .confirming: String(localized: "Confirming")
            case .offline: String(localized: "Offline")
            }
        }

        var status: NetworkStatus {
            switch self {
            case .online: .online(.preview)
            case .confirming: .verifying(previous: .preview, candidateAddress: "198.51.100.8")
            case .offline: .offline(previous: .preview)
            }
        }
    }
}

// MARK: - 菜单栏仿真

/// 一小块“桌面 + 菜单栏”：Prism 图标使用与真实菜单栏同一套绘制，样式切换时交叉淡化。
private struct MenuBarMockup: View {
    let presentation: MenuBarPresentation
    let flagStyle: CountryFlagStyle
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Spacer(minLength: 0)
                prismItem
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Image(systemName: "switch.2")
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .monospacedDigit()
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(colorScheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.55))
            Spacer(minLength: 0)
        }
        .frame(height: 78)
        .background(wallpaper)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .environment(\.colorScheme, colorScheme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Menu Bar Preview"))
        .accessibilityValue(presentation.title)
    }

    private var wallpaper: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.12, green: 0.14, blue: 0.24), Color(red: 0.24, green: 0.16, blue: 0.32)]
                    : [Color(red: 0.62, green: 0.76, blue: 0.96), Color(red: 0.93, green: 0.78, blue: 0.86)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.accentColor.opacity(0.45), .clear],
                center: UnitPoint(x: 0.82, y: 1.1),
                startRadius: 4,
                endRadius: 180
            )
        }
    }

    private var prismItem: some View {
        HStack(spacing: 4) {
            indicator
            if !presentation.title.isEmpty {
                Text(presentation.title)
                    .contentTransition(.opacity)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: presentation)
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.3), value: flagStyle)
        .accessibilityIdentifier("settings.menuBar.preview")
    }

    @ViewBuilder
    private var indicator: some View {
        switch presentation.indicator {
        case .none:
            EmptyView()
        case .flag(let countryCode):
            ZStack(alignment: .bottomTrailing) {
                if let image = MenuBarFlagImageFactory.flagImage(
                    for: countryCode,
                    style: flagStyle,
                    appearance: NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
                ) {
                    Image(nsImage: image)
                        .interpolation(flagStyle == .pixel ? .none : .high)
                }
                if let badge = presentation.badge {
                    Circle()
                        .fill(badgeColor(badge))
                        .frame(width: 6, height: 6)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                        .offset(x: 1, y: 0)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .id("\(flagStyle.rawValue)/\(countryCode)")
            .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
        case .systemSymbol(let name):
            Image(systemName: name)
        }
    }

    private func badgeColor(_ badge: MenuBarStatusBadge) -> Color {
        switch badge {
        case .confirming: StatusPalette.confirming
        case .stale: StatusPalette.stale
        case .guardAlert: StatusPalette.offline
        }
    }
}

// MARK: - 国旗风格

/// 四列风格网格：选中框在格子之间滑动，选中的旗面轻弹一下。
private struct FlagStyleGrid: View {
    @Binding var selection: CountryFlagStyle
    let sampleCountryCode: String
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = 0

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
            spacing: 8
        ) {
            ForEach(CountryFlagStyle.allCases) { style in
                FlagStyleTile(
                    style: style,
                    sampleCountryCode: sampleCountryCode,
                    isSelected: selection == style,
                    namespace: namespace,
                    bounce: bounce
                ) {
                    guard selection != style else { return }
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.25)) {
                        selection = style
                    }
                    bounce += 1
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Country flag style"))
        .accessibilityIdentifier("settings.menuBar.flagStyle")
    }
}

private struct FlagStyleTile: View {
    let style: CountryFlagStyle
    let sampleCountryCode: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let bounce: Int
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                CountryFlagView(
                    countryCode: sampleCountryCode,
                    style: style,
                    diameter: 26,
                    containerSize: CGSize(width: 40, height: 30)
                )
                .keyframeAnimator(initialValue: 1.0, trigger: bounce) { content, scale in
                    content.scaleEffect(isSelected ? scale : 1)
                } keyframes: { _ in
                    if reduceMotion {
                        LinearKeyframe(1.0, duration: 0.01)
                    } else {
                        SpringKeyframe(1.18, duration: 0.14)
                        SpringKeyframe(1.0, duration: 0.32, spring: .bouncy)
                    }
                }
                .offset(y: isHovered && !reduceMotion ? -1.5 : 0)
                Text(style.label)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
                if isSelected {
                    shape
                        .fill(.tint.opacity(0.1))
                        .overlay(shape.strokeBorder(.tint, lineWidth: 1.5))
                        .matchedGeometryEffect(id: "flag-style-selection", in: namespace)
                } else {
                    shape.fill(Color.primary.opacity(isHovered ? 0.06 : 0.03))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { isHovered = hovering }
        }
        .help(style.label)
        .accessibilityLabel(style.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("settings.menuBar.flagStyle.\(style.rawValue)")
    }
}
