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
                case .network: NetworkSettingsView()
                case .privacy: PrivacySettingsView()
                }
            }
            .id(selection)
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .frame(width: 620, height: preferredHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(settings.accentColorChoice.color)
        .navigationTitle(selection.title)
        .background(SettingsWindowAccessor { environment.registerSettingsWindow($0) })
    }

    private var preferredHeight: CGFloat {
        switch selection {
        case .general:
            settings.automaticRefreshEnabled ? 540 : 500
        case .menuBar:
            settings.menuBarDisplayMode == .custom ? 620 : 500
        case .appearance:
            340
        case .network, .privacy:
            560
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case menuBar
    case appearance
    case network
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .menuBar: String(localized: "Menu Bar")
        case .appearance: String(localized: "Appearance")
        case .network: String(localized: "Network")
        case .privacy: String(localized: "Privacy")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .appearance: "paintbrush.fill"
        case .network: "network"
        case .privacy: "lock.shield"
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
