import SwiftUI

struct SettingsRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings
    @State private var selection: SettingsSection = .general

    /// 设置窗口的固定尺寸，与 macOS 系统设置类应用的常见比例一致。
    static let windowSize = CGSize(width: 620, height: 600)

    var body: some View {
        VStack(spacing: 0) {
            SettingsNavigationBar(selection: $selection)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

            Divider()

            Group {
                switch selection {
                case .general: GeneralSettingsView()
                case .menuBar: MenuBarSettingsView()
                case .appearance: AppearanceSettingsView()
                case .about: AboutSettingsView()
                }
            }
            // 所有标签页共用同一窗口尺寸，切换时窗口不再伸缩；内容较多的页面在页内滚动。
            .id(selection)
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(settings.accentColorChoice.color)
        .navigationTitle(selection.title)
        .background(SettingsWindowAccessor { environment.registerSettingsWindow($0) })
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case menuBar
    case appearance
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .menuBar: String(localized: "Menu Bar")
        case .appearance: String(localized: "Appearance")
        case .about: String(localized: "About")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .appearance: "paintpalette"
        case .about: "info.circle"
        }
    }

}

private struct SettingsNavigationBar: View {
    @Environment(SettingsStore.self) private var settings
    @Binding var selection: SettingsSection
    @FocusState private var focusedSection: SettingsSection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 切换页面时内容交叉淡入，窗口尺寸保持不变。
    private func select(_ section: SettingsSection) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.26)) {
            selection = section
        }
        focusedSection = section
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SettingsSection.allCases) { section in
                let isSelected = selection == section
                Button {
                    select(section)
                } label: {
                    // 图标放在固定尺寸的槽位里，不同符号的视觉高度不再把文字顶得高低不一；
                    // 字重也固定，选中只改变颜色与底色，标签宽度不会跳动。
                    VStack(spacing: 4) {
                        Image(systemName: section.systemImage)
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 17, weight: .regular))
                            .frame(width: 28, height: 22)
                        Text(section.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? settings.accentColorChoice.theme.primary : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isSelected ? settings.accentColorChoice.theme.softBackground : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .focused($focusedSection, equals: section)
                .accessibilityLabel(section.title)
                .accessibilityIdentifier("settings.section.\(section.rawValue)")
                .accessibilityValue(isSelected ? String(localized: "Selected") : "")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .onMoveCommand { direction in
            guard direction == .left || direction == .right,
                  let currentIndex = SettingsSection.allCases.firstIndex(of: selection) else { return }
            let delta = direction == .left ? -1 : 1
            let nextIndex = min(max(currentIndex + delta, 0), SettingsSection.allCases.count - 1)
            select(SettingsSection.allCases[nextIndex])
        }
    }
}

/// 设置窗口挂载时回调一次，用于把窗口激活并置于最前。
private struct SettingsWindowAccessor: NSViewRepresentable {
    let onAttach: (NSWindow) -> Void

    func makeNSView(context: Context) -> AttachView {
        let view = AttachView()
        view.onAttach = onAttach
        return view
    }

    func updateNSView(_ nsView: AttachView, context: Context) {}

    final class AttachView: NSView {
        var onAttach: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            onAttach?(window)
        }
    }
}
