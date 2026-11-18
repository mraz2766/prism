import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace

    var body: some View {
        SettingsPage {
            SettingsGroup(title: String(localized: "Color scheme"), systemImage: "circle.lefthalf.filled") {
                HStack(spacing: 10) {
                    ForEach(AppearanceMode.allCases) { mode in
                        AppearanceModeCard(
                            mode: mode,
                            isSelected: settings.appearanceMode == mode,
                            namespace: namespace
                        ) {
                            withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.25)) {
                                settings.appearanceMode = mode
                            }
                        }
                    }
                }
                .padding(10)
            }

            SettingsGroup(title: String(localized: "Accent color"), systemImage: "paintbrush") {
                HStack(spacing: 12) {
                    Text(settings.accentColorChoice.label)
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: settings.accentColorChoice)
                        .accessibilityIdentifier("settings.accent.selection")
                    Spacer(minLength: 12)
                    HStack(spacing: 8) {
                        ForEach(AccentColorChoice.allCases) { choice in
                            AccentColorDot(
                                choice: choice,
                                isSelected: settings.accentColorChoice == choice,
                                namespace: namespace
                            ) {
                                withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.3)) {
                                    settings.accentColorChoice = choice
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                SettingsDivider()
                accentPreview
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        }
    }

    /// 用几个真实控件展示强调色的实际效果，颜色切换时一起过渡。
    private var accentPreview: some View {
        HStack(spacing: 12) {
            Text(String(localized: "Preview"))
                .foregroundStyle(.secondary)
            Spacer()
            Label(String(localized: "Online"), systemImage: "checkmark.circle.fill")
                .tagCapsule(foreground: .tint, background: .tint.opacity(TagCapsuleMetrics.backgroundOpacity))
            Toggle(String(localized: "Preview"), isOn: .constant(true))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .allowsHitTesting(false)
            Button(String(localized: "Start test")) {}
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }
}

/// 外观模式缩略图：一扇迷你窗口，“跟随系统”左右各半。选中框在三张卡片之间滑动。
private struct AppearanceModeCard: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                thumbnail
                    .frame(height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                    .scaleEffect(isHovered && !reduceMotion ? 1.03 : 1)
                Text(mode.label)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background {
                let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                if isSelected {
                    shape
                        .fill(.tint.opacity(0.08))
                        .overlay(shape.strokeBorder(.tint, lineWidth: 1.5))
                        .matchedGeometryEffect(id: "appearance-selection", in: namespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { isHovered = hovering }
        }
        .accessibilityLabel(mode.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("settings.appearance.\(mode.rawValue)")
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch mode {
        case .light: MiniWindow(dark: false)
        case .dark: MiniWindow(dark: true)
        case .system:
            ZStack {
                MiniWindow(dark: false)
                MiniWindow(dark: true)
                    .mask(
                        GeometryReader { proxy in
                            Path { path in
                                path.move(to: CGPoint(x: proxy.size.width * 0.62, y: 0))
                                path.addLine(to: CGPoint(x: proxy.size.width, y: 0))
                                path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                                path.addLine(to: CGPoint(x: proxy.size.width * 0.38, y: proxy.size.height))
                                path.closeSubpath()
                            }
                        }
                    )
            }
        }
    }
}

/// 缩略窗口：桌面渐变底 + 标题栏三个圆点 + 侧栏与几行内容。
private struct MiniWindow: View {
    let dark: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: dark
                    ? [Color(red: 0.16, green: 0.18, blue: 0.3), Color(red: 0.3, green: 0.2, blue: 0.38)]
                    : [Color(red: 0.66, green: 0.8, blue: 0.98), Color(red: 0.96, green: 0.82, blue: 0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 2.5) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { color in
                        Circle().fill(color.opacity(0.85)).frame(width: 4, height: 4)
                    }
                }
                .padding(4)
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 3) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor).frame(width: 26, height: 4)
                        RoundedRectangle(cornerRadius: 1.5).fill(line).frame(width: 40, height: 3)
                        RoundedRectangle(cornerRadius: 1.5).fill(line).frame(width: 32, height: 3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(dark ? Color(white: 0.17) : Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            )
            .padding(.top, 10)
            .padding(.leading, 12)
            .padding(.trailing, -6)
        }
    }

    private var line: Color { dark ? Color.white.opacity(0.28) : Color.black.opacity(0.16) }
}

/// 强调色圆点：选中环在圆点之间滑动。
private struct AccentColorDot: View {
    let choice: AccentColorChoice
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Circle()
                        .strokeBorder(choice.color, lineWidth: 2)
                        .frame(width: 26, height: 26)
                        .matchedGeometryEffect(id: "accent-ring", in: namespace)
                }
                Circle()
                    .fill(choice.color)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
                    .scaleEffect(isHovered && !isSelected && !reduceMotion ? 1.12 : 1)
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .help(choice.label)
        .accessibilityLabel(choice.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("settings.accent.\(choice.rawValue)")
    }
}
