import SwiftUI

struct SettingsRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings
    @State private var selection: SettingsSection = .general

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
            // 高度由每页内容决定，文字变长或展开折叠区时不会被裁切。
            .fixedSize(horizontal: false, vertical: true)
            .id(selection)
            .transition(.opacity)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(width: 620)
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
        case .appearance: "paintbrush.fill"
        case .about: "info.circle"
        }
    }

}

private struct SettingsNavigationBar: View {
    @Environment(SettingsStore.self) private var settings
    @Binding var selection: SettingsSection
    @FocusState private var focusedSection: SettingsSection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 切换页面时窗口高度随内容平滑过渡，内容交叉淡入。
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
                    VStack(spacing: 5) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                        Text(section.title)
                            .font(.caption.weight(isSelected ? .semibold : .medium))
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
